import { createServer } from "node:http";
import { execFile } from "node:child_process";
import { readFile } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";
import { promisify } from "node:util";
import { mapTailscaleStatusToHosts } from "./telemetry.js";

const root = resolve(new URL("..", import.meta.url).pathname.slice(1));
const execFileAsync = promisify(execFile);
const previousCounters = new Map();
const mimeTypes = new Map([
  [".html", "text/html; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
]);

export function resolveStaticRequest(urlPath) {
  if (urlPath.includes("..")) return { kind: "not-found" };
  const cleanPath = decodeURIComponent(new URL(urlPath, "http://tailops.local").pathname);
  if (cleanPath === "/api/agents") {
    return {
      kind: "agents",
      path: join(root, "data", "agents.sample.json"),
      contentType: "application/json; charset=utf-8",
    };
  }
  if (cleanPath === "/api/telemetry") {
    return {
      kind: "telemetry",
      contentType: "application/json; charset=utf-8",
    };
  }
  if (cleanPath === "/.well-known/agent.json" || cleanPath === "/.well-known/agent-card.json") {
    return {
      kind: "agent-card",
      contentType: "application/json; charset=utf-8",
    };
  }

  const relative = cleanPath === "/" ? "index.html" : cleanPath.slice(1);
  const normalized = normalize(relative);
  if (normalized.startsWith("..") || normalized.includes(":") || normalized.startsWith("\\")) {
    return { kind: "not-found" };
  }

  const filePath = join(root, normalized);
  if (!filePath.startsWith(root)) return { kind: "not-found" };

  return {
    kind: "file",
    path: filePath,
    contentType: mimeTypes.get(extname(filePath)) ?? "application/octet-stream",
  };
}

function calculateRates(status, now = Date.now()) {
  const peers = [status.Self, ...Object.values(status.Peer ?? {})].filter(Boolean);
  const rates = new Map();
  for (const peer of peers) {
    const id = peer.ID || peer.PublicKey || peer.DNSName || peer.HostName;
    if (!id) continue;
    const previous = previousCounters.get(id);
    const rxBytes = peer.RxBytes ?? 0;
    const txBytes = peer.TxBytes ?? 0;
    if (previous && now > previous.timestamp) {
      const seconds = (now - previous.timestamp) / 1000;
      rates.set(id, {
        networkInMbps: Math.max(0, ((rxBytes - previous.rxBytes) * 8) / seconds / 1_000_000),
        networkOutMbps: Math.max(0, ((txBytes - previous.txBytes) * 8) / seconds / 1_000_000),
      });
    }
    previousCounters.set(id, { rxBytes, txBytes, timestamp: now });
  }
  return rates;
}

async function getLocalMetrics() {
  if (process.platform !== "win32") return {};
  try {
    const script = [
      "$cpu=(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average",
      "$os=Get-CimInstance Win32_OperatingSystem",
      "$mem=[math]::Round((($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100)",
      "$thermal=$null",
      "try { $t=Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | Select-Object -First 1; if ($t) { $thermal=[math]::Round(($t.CurrentTemperature/10)-273.15) } } catch {}",
      "[pscustomobject]@{cpu=[math]::Round($cpu);memory=$mem;cpuTempC=$thermal} | ConvertTo-Json -Compress",
    ].join("; ");
    const { stdout } = await execFileAsync("powershell.exe", ["-NoProfile", "-Command", script], { timeout: 5000 });
    return JSON.parse(stdout);
  } catch {
    return {};
  }
}

async function getLiveTelemetry() {
  const { stdout } = await execFileAsync("tailscale", ["status", "--json"], { timeout: 8000 });
  const status = JSON.parse(stdout);
  const localMetrics = await getLocalMetrics();
  const ratesById = calculateRates(status);
  return {
    schema: "tailops.telemetry.v1",
    source: "tailscale-cli",
    generatedAt: new Date().toISOString(),
    tailnet: {
      name: status.CurrentTailnet?.Name ?? null,
      magicDnsSuffix: status.MagicDNSSuffix ?? null,
      backendState: status.BackendState ?? null,
      health: status.Health ?? [],
    },
    hosts: mapTailscaleStatusToHosts(status, { localMetrics, ratesById }),
  };
}

function getAgentCard(request) {
  const host = request.headers.host ?? "127.0.0.1:4173";
  const proto = request.headers["x-forwarded-proto"] ?? "http";
  const baseUrl = `${proto}://${host}`;
  return {
    name: "TailOps Monitor",
    description: "Local tailnet observability and AI agent phonebook for Tailscale-connected hosts.",
    version: "0.1.0",
    url: baseUrl,
    provider: {
      organization: "StoneHub",
      url: "https://github.com/stonehub",
    },
    capabilities: {
      streaming: false,
      pushNotifications: false,
      stateTransitionHistory: false,
    },
    defaultInputModes: ["application/json", "text/plain"],
    defaultOutputModes: ["application/json"],
    skills: [
      {
        id: "tailnet-telemetry",
        name: "Tailnet telemetry",
        description: "Returns live Tailscale peer status, MagicDNS names, online state, relay state, traffic counters, and local host CPU/memory when available.",
        tags: ["tailscale", "telemetry", "network", "observability"],
        examples: ["GET /api/telemetry"],
      },
      {
        id: "agent-phonebook",
        name: "Agent phonebook",
        description: "Returns local AI agent contact entries by host, endpoint, availability, and capability tags.",
        tags: ["agents", "phonebook", "mcp", "a2a", "openclaw"],
        examples: ["GET /api/agents"],
      },
    ],
    supportedInterfaces: [
      {
        url: `${baseUrl}/api/telemetry`,
        protocolBinding: "REST",
        protocolVersion: "1.0.0",
      },
      {
        url: `${baseUrl}/api/agents`,
        protocolBinding: "REST",
        protocolVersion: "1.0.0",
      },
    ],
    securitySchemes: {
      tailnetOrLan: {
        type: "network",
        description: "Designed for trusted LAN or Tailscale-only access. Do not expose publicly without authentication.",
      },
    },
  };
}

export function createTailopsServer() {
  return createServer(async (request, response) => {
    const result = resolveStaticRequest(request.url ?? "/");
    if (result.kind === "not-found") {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("Not found");
      return;
    }

    if (result.kind === "telemetry") {
      try {
        const telemetry = await getLiveTelemetry();
        response.writeHead(200, {
          "content-type": result.contentType,
          "cache-control": "no-store",
          "access-control-allow-origin": "*",
        });
        response.end(JSON.stringify(telemetry, null, 2));
      } catch (error) {
        response.writeHead(503, {
          "content-type": "application/json; charset=utf-8",
          "cache-control": "no-store",
          "access-control-allow-origin": "*",
        });
        response.end(JSON.stringify({ schema: "tailops.telemetry.v1", source: "unavailable", error: error.message }, null, 2));
      }
      return;
    }

    if (result.kind === "agent-card") {
      response.writeHead(200, {
        "content-type": result.contentType,
        "cache-control": "no-store",
        "access-control-allow-origin": "*",
      });
      response.end(JSON.stringify(getAgentCard(request), null, 2));
      return;
    }

    try {
      const content = await readFile(result.path);
      response.writeHead(200, {
        "content-type": result.contentType,
        "cache-control": result.kind === "agents" ? "no-store" : "no-cache",
        "access-control-allow-origin": "*",
      });
      response.end(content);
    } catch {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("Not found");
    }
  });
}

