import {
  createTelemetrySnapshot,
  formatMbps,
  getTopActiveHost,
  normalizeCpuTemperature,
  summarizeLocalNetwork,
} from "./telemetry.js";
import {
  getNodeLabelPolicy,
  getScreenMode,
} from "./layout.js";
import {
  buildAgentDirectory,
  getReachableAgents,
  sampleAgentHosts,
  serializeAgentDirectory,
  summarizeAgentDirectory,
} from "./agents.js";

const meshCanvas = document.querySelector("#meshCanvas");
const meshCtx = meshCanvas.getContext("2d");
const dashboard = document.querySelector(".dashboard");
const spotlightChart = document.querySelector("#spotlightChart").getContext("2d");
const throughputChart = document.querySelector("#throughputChart").getContext("2d");
const routerChart = document.querySelector("#routerChart").getContext("2d");
const deviceChart = document.querySelector("#deviceChart").getContext("2d");
const directory = buildAgentDirectory(sampleAgentHosts);
const reachableAgents = getReachableAgents(directory);
const agentSummary = summarizeAgentDirectory(directory);
const agentJson = serializeAgentDirectory(directory);
const appState = {
  liveHosts: null,
  telemetrySource: "demo",
  lastTelemetryAt: null,
};
const renderState = {
  hosts: [],
  topHost: null,
  width: 0,
  height: 0,
  hoveredHost: null,
  screenMode: "wide",
};
const nodeTooltip = document.querySelector("#nodeTooltip");

document.querySelector("#tailops-agent-directory").textContent = agentJson;
window.tailopsAgentDirectory = JSON.parse(agentJson);
window.tailopsReachableAgents = reachableAgents;

async function pollLiveTelemetry() {
  if (window.location.protocol === "file:") return;
  try {
    const response = await fetch("/api/telemetry", { cache: "no-store" });
    if (!response.ok) throw new Error(`telemetry ${response.status}`);
    const telemetry = await response.json();
    if (Array.isArray(telemetry.hosts) && telemetry.hosts.length > 0) {
      appState.liveHosts = telemetry.hosts;
      appState.telemetrySource = telemetry.source ?? "live";
      appState.lastTelemetryAt = telemetry.generatedAt ?? new Date().toISOString();
    }
  } catch {
    appState.telemetrySource = "demo";
  }
}

function buildLinks(hosts, topHost) {
  const self = hosts.find((host) => host.role === "This device") ?? hosts[0];
  const hub = hosts.find((host) => host.subnetRoutes || host.exitNode) ?? self;
  const links = [];
  for (const host of hosts) {
    if (host.id !== hub.id) links.push([hub.id, host.id]);
  }
  if (topHost && topHost.id !== hub.id) {
    for (const host of hosts.filter((candidate) => candidate.id !== topHost.id && candidate.id !== hub.id).slice(0, 3)) {
      links.push([topHost.id, host.id]);
    }
  }
  return links;
}

function resizeCanvas(canvas, ctx) {
  const ratio = Math.max(1, window.devicePixelRatio || 1);
  const rect = canvas.getBoundingClientRect();
  canvas.width = Math.round(rect.width * ratio);
  canvas.height = Math.round(rect.height * ratio);
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
}

function pointFor(host, width, height) {
  return {
    x: host.x * width,
    y: host.y * height,
  };
}

function colorForHost(host) {
  const temp = normalizeCpuTemperature(host.cpuTempC);
  if (host.status === "offline") return "#ff5b75";
  if (host.status === "warning" || temp.level === "hot") return "#ffae3d";
  if (host.homeAssistant || host.os === "asuswrt" || /router/i.test(host.role ?? "")) return "#2dd4bf";
  if (host.os === "android") return "#ff67b3";
  if (host.os === "windows") return "#4188ff";
  if (host.os === "macOS") return "#a778ff";
  if (temp.level === "warm") return "#37d7ff";
  return temp.level === "unknown" ? "#37d7ff" : "#3ee88a";
}

function applyScreenMode(mode) {
  if (renderState.screenMode === mode && dashboard.classList.contains(`mode-${mode}`)) return;
  renderState.screenMode = mode;
  dashboard.classList.remove("mode-wide", "mode-compact", "mode-tiny");
  dashboard.classList.add(`mode-${mode}`);
}

function truncateLabel(value, maxLength) {
  const text = String(value ?? "");
  if (text.length <= maxLength) return text;
  return `${text.slice(0, Math.max(1, maxLength - 1))}…`;
}

function nodeRadius(host, topHost, mode = renderState.screenMode) {
  const isTop = host.id === topHost?.id;
  if (mode === "tiny") return isTop ? 27 : 14;
  if (mode === "compact") return isTop ? 31 : 17;
  return isTop ? 35 : 19;
}

function drawRing(ctx, x, y, radius, pct, color, start = -Math.PI / 2) {
  const safePct = typeof pct === "number" && Number.isFinite(pct) ? pct : 0;
  ctx.beginPath();
  ctx.strokeStyle = "rgba(130, 146, 173, 0.18)";
  ctx.lineWidth = 3;
  ctx.arc(x, y, radius, 0, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  ctx.strokeStyle = color;
  ctx.lineWidth = 3;
  ctx.lineCap = "round";
  ctx.arc(x, y, radius, start, start + Math.PI * 2 * safePct);
  ctx.stroke();
}

function drawFlows(ctx, hosts, topHost, time, width, height) {
  const links = buildLinks(hosts, topHost);
  const map = new Map(hosts.map((host) => [host.id, { host, ...pointFor(host, width, height) }]));
  for (const [fromId, toId] of links) {
    const from = map.get(fromId);
    const to = map.get(toId);
    if (!from || !to) continue;
    const traffic = (((from.host.networkInMbps ?? 0) + (from.host.networkOutMbps ?? 0) + (to.host.networkInMbps ?? 0) + (to.host.networkOutMbps ?? 0)) / 2000);
    const intensity = Math.min(1, 0.18 + traffic * 0.14);
    const isTop = fromId === topHost.id || toId === topHost.id;
    const isRouter = from.host.homeAssistant || to.host.homeAssistant || from.host.os === "asuswrt" || to.host.os === "asuswrt";
    const pulse = (Math.sin(time / 420 + from.x * 0.01) + 1) / 2;

    ctx.beginPath();
    ctx.moveTo(from.x, from.y);
    const midX = (from.x + to.x) / 2 + Math.sin(time / 1400 + from.y) * 22;
    const midY = (from.y + to.y) / 2 + Math.cos(time / 1600 + to.x) * 18;
    ctx.quadraticCurveTo(midX, midY, to.x, to.y);
    ctx.strokeStyle = isTop
      ? `rgba(55, 215, 255, ${0.32 + pulse * 0.38})`
      : isRouter
        ? `rgba(45, 212, 191, ${0.24 + pulse * 0.18})`
        : `rgba(80, 118, 164, ${intensity})`;
    ctx.lineWidth = isTop ? 2.4 + pulse * 1.8 : 1.1 + intensity * 1.8;
    ctx.shadowColor = isTop ? "rgba(55, 215, 255, 0.75)" : "transparent";
    ctx.shadowBlur = isTop ? 12 : 0;
    ctx.stroke();
    ctx.shadowBlur = 0;
  }
}

function drawNode(ctx, host, topHost, hoveredHost, screenMode, time, width, height) {
  const { x, y } = pointFor(host, width, height);
  const isTop = host.id === topHost.id;
  const isHovered = host.id === hoveredHost?.id;
  const color = colorForHost(host);
  const thermal = normalizeCpuTemperature(host.cpuTempC);
  const pulse = (Math.sin(time / 520) + 1) / 2;
  const radius = nodeRadius(host, topHost, screenMode);
  const label = getNodeLabelPolicy(screenMode);

  if (isTop || isHovered) {
    for (let i = 0; i < 3; i += 1) {
      ctx.beginPath();
      ctx.strokeStyle = isHovered ? `rgba(55, 215, 255, ${0.2 - i * 0.04})` : `rgba(255, 174, 61, ${0.16 - i * 0.04})`;
      ctx.lineWidth = 2;
      ctx.arc(x, y, radius + 18 + i * 18 + pulse * 9, 0, Math.PI * 2);
      ctx.stroke();
    }
  }

  ctx.beginPath();
  ctx.fillStyle = isTop ? "rgba(9, 20, 43, 0.96)" : "rgba(10, 18, 36, 0.86)";
  ctx.strokeStyle = isHovered ? color : isTop ? "rgba(255, 174, 61, 0.85)" : "rgba(130, 146, 173, 0.5)";
  ctx.lineWidth = isTop || isHovered ? 2 : 1;
  ctx.shadowColor = isHovered ? color : isTop ? "rgba(255, 174, 61, 0.55)" : "rgba(55, 215, 255, 0.22)";
  ctx.shadowBlur = isTop || isHovered ? 28 : 12;
  ctx.roundRect(x - radius, y - radius, radius * 2, radius * 2, 8);
  ctx.fill();
  ctx.stroke();
  ctx.shadowBlur = 0;

  drawRing(ctx, x, y, radius + 7, (host.cpu ?? 0) / 100, "#4188ff");
  drawRing(ctx, x, y, radius + 12, (host.memory ?? 0) / 100, "#37d7ff", -Math.PI / 2 + 0.4);
  drawRing(ctx, x, y, radius + 17, thermal.normalized / 100, color, -Math.PI / 2 + 0.8);

  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x + radius - 6, y - radius + 6, isTop ? 5 : 4, 0, Math.PI * 2);
  ctx.fill();

  ctx.fillStyle = isTop ? "#ffffff" : "rgba(220, 232, 255, 0.82)";
  ctx.font = isTop ? `700 ${13 * label.fontScale}px Inter, sans-serif` : `600 ${11 * label.fontScale}px Inter, sans-serif`;
  ctx.textAlign = "center";
  ctx.fillText(truncateLabel(host.name, label.maxLength), x, y + radius + (screenMode === "tiny" ? 24 : 32));
  if (label.showSecondary) {
    ctx.fillStyle = "rgba(130, 146, 173, 0.86)";
    ctx.font = "10px Inter, sans-serif";
    ctx.fillText(host.cpuTempC == null ? `${host.os ?? "peer"} / temp unknown` : `${host.cpuTempC}C CPU temp`, x, y + radius + 47);
  }
}

function escapeHtml(value) {
  return String(value ?? "--").replace(/[&<>"']/g, (char) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    "\"": "&quot;",
    "'": "&#39;",
  }[char]));
}

function formatValue(value, suffix = "") {
  if (value == null || value === "") return "--";
  return `${value}${suffix}`;
}

function formatLatency(value) {
  return value == null ? "--" : `${value}ms`;
}

function hostTooltipHtml(host) {
  const totalNet = (host.networkInMbps ?? 0) + (host.networkOutMbps ?? 0);
  const router = host.homeAssistant;
  const fields = [
    ["Role", host.role ?? host.os ?? "peer"],
    ["OS", host.os ?? "unknown"],
    ["IP", host.tailscaleIp ?? "not routed"],
    ["MagicDNS", host.magicDns ?? "--"],
    ["Latency", formatLatency(host.latencyMs)],
    ["Relay", host.relay || "--"],
    ["Traffic", formatMbps(totalNet)],
    ["CPU / MEM", `${formatValue(host.cpu, "%")} / ${formatValue(host.memory, "%")}`],
    ["Temp", host.cpuTempC == null ? "--" : `${host.cpuTempC}C`],
    ["Uptime", host.uptime ?? "--"],
  ];
  if (router) {
    fields.push(["WAN", router.wan?.connected ? "connected" : "unknown"]);
    fields.push(["Wi-Fi clients", router.devicesConnected ?? "--"]);
    fields.push(["External IP", router.externalIp ?? "--"]);
  }
  const tags = [
    ...(host.tags ?? []),
    host.exitNode ? "exit-node" : null,
    host.subnetRoutes ? "subnet-routes" : null,
  ].filter(Boolean);

  return `
    <div class="tooltip-top">
      <div>
        <strong>${escapeHtml(host.name)}</strong>
        <p class="tooltip-role">${escapeHtml(host.role ?? host.os ?? "Tailnet peer")}</p>
      </div>
      <span class="status-chip" style="background:${escapeHtml(colorForHost(host))}">${escapeHtml(host.status ?? "unknown")}</span>
    </div>
    <div class="tooltip-grid">
      ${fields.map(([label, value]) => `<div><span>${escapeHtml(label)}</span><strong>${escapeHtml(value)}</strong></div>`).join("")}
    </div>
    <div class="tooltip-tags">${tags.slice(0, 8).map((tag) => `<span>${escapeHtml(tag)}</span>`).join("")}</div>
  `;
}

function positionTooltip(host, clientX, clientY) {
  nodeTooltip.innerHTML = hostTooltipHtml(host);
  const margin = 14;
  const rect = meshCanvas.getBoundingClientRect();
  const tooltipWidth = renderState.screenMode === "tiny" ? 280 : 310;
  const estimatedHeight = host.homeAssistant ? 298 : 252;
  const left = Math.min(rect.width - tooltipWidth - margin, Math.max(margin, clientX - rect.left + 18));
  const top = Math.min(rect.height - estimatedHeight - margin, Math.max(82, clientY - rect.top + 18));
  nodeTooltip.style.left = `${left}px`;
  nodeTooltip.style.top = `${top}px`;
  nodeTooltip.classList.add("visible");
}

function hitTestHost(clientX, clientY) {
  const rect = meshCanvas.getBoundingClientRect();
  const x = clientX - rect.left;
  const y = clientY - rect.top;
  let closest = null;
  for (const host of renderState.hosts) {
    const point = pointFor(host, renderState.width, renderState.height);
    const radius = nodeRadius(host, renderState.topHost) + 22;
    const distance = Math.hypot(point.x - x, point.y - y);
    if (distance <= radius && (!closest || distance < closest.distance)) {
      closest = { host, distance };
    }
  }
  return closest?.host ?? null;
}

function drawChart(ctx, values, color, fill, width, height) {
  ctx.clearRect(0, 0, width, height);
  ctx.strokeStyle = "rgba(130,146,173,0.18)";
  ctx.lineWidth = 1;
  for (let i = 1; i < 4; i += 1) {
    const y = (height / 4) * i;
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
    ctx.stroke();
  }
  ctx.beginPath();
  values.forEach((value, index) => {
    const x = (index / (values.length - 1)) * width;
    const y = height - value * height;
    if (index === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  });
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.lineTo(width, height);
  ctx.lineTo(0, height);
  ctx.closePath();
  ctx.fillStyle = fill;
  ctx.fill();
}

function updateDom(hosts, topHost, time) {
  const localNetwork = summarizeLocalNetwork(hosts);
  const agentText = reachableAgents.map((agent) => `${agent.type} on ${agent.host}`).join(" • ");
  const netTotal = (topHost.networkInMbps ?? 0) + (topHost.networkOutMbps ?? 0);
  document.querySelector("#clock").textContent = new Intl.DateTimeFormat([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }).format(new Date());
  document.querySelector("#agentCount").textContent = `${appState.telemetrySource === "tailscale-cli" ? "live Tailscale" : "demo"} • ${reachableAgents.length} agents reachable`;
  document.querySelector("#topHostName").textContent = topHost.name;
  document.querySelector("#topScore").textContent = topHost.score;
  document.querySelector("#topReason").textContent = topHost.reason;
  document.querySelector("#metricCpu").textContent = topHost.cpu == null ? "--" : `${topHost.cpu}%`;
  document.querySelector("#metricMemory").textContent = topHost.memory == null ? "--" : `${topHost.memory}%`;
  document.querySelector("#metricTemp").textContent = topHost.cpuTempC == null ? "--" : `${topHost.cpuTempC}C`;
  document.querySelector("#metricLatency").textContent = topHost.latencyMs == null ? "--" : `${topHost.latencyMs}ms`;
  document.querySelector("#metricDiskIo").textContent = formatMbps(topHost.diskIoMbps);
  document.querySelector("#metricNet").textContent = formatMbps(netTotal);
  document.querySelector("#globalThroughput").textContent = formatMbps(hosts.reduce((sum, host) => sum + (host.networkInMbps ?? 0) + (host.networkOutMbps ?? 0), 0));
  const latencyHosts = hosts.filter((host) => typeof host.latencyMs === "number");
  document.querySelector("#meshLatency").textContent = latencyHosts.length === 0 ? "--" : `${(latencyHosts.reduce((sum, host) => sum + host.latencyMs, 0) / latencyHosts.length).toFixed(1)} ms avg`;
  document.querySelector("#agentStrip").innerHTML = `<strong>Agent phonebook:</strong> ${escapeHtml(agentText)}. JSON available at window.tailopsAgentDirectory.`;
  document.querySelector("#routerName").textContent = localNetwork.router?.name ?? "No router host";
  document.querySelector("#routerWan").textContent = localNetwork.router?.wanConnected ? "online" : "--";
  document.querySelector("#routerClients").textContent = localNetwork.router?.devicesConnected ?? "--";
  document.querySelector("#routerDown").textContent = formatMbps(localNetwork.router?.networkInMbps);
  document.querySelector("#routerUp").textContent = formatMbps(localNetwork.router?.networkOutMbps);
  document.querySelector("#routerMeta").textContent = localNetwork.router
    ? `${localNetwork.onlineHosts}/${localNetwork.hostCount} hosts online • external ${localNetwork.router.externalIp ?? "--"}`
    : `${localNetwork.onlineHosts}/${localNetwork.hostCount} hosts online • router not discovered`;
  document.querySelector("#hostHealthCount").textContent = `${hosts.length} nodes`;
  document.querySelector("#agentSummary").textContent = `${agentSummary.availableAgents}/${agentSummary.totalAgents} available`;
  document.querySelector("#agentCapabilityLine").textContent = `${agentSummary.capabilities.length} capabilities • ${agentSummary.capabilities.slice(0, 5).join(", ")}`;

  const heatmap = document.querySelector("#healthHeatmap");
  heatmap.replaceChildren(...hosts.map((host) => {
    const temp = normalizeCpuTemperature(host.cpuTempC);
    const cell = document.createElement("div");
    cell.className = "heat-cell";
    cell.dataset.host = host.name;
    cell.style.background = `linear-gradient(180deg, ${colorForHost(host)}, rgba(65,136,255,0.18))`;
    cell.style.opacity = String(0.45 + temp.normalized / 180);
    return cell;
  }));

  const agentList = document.querySelector("#agentList");
  agentList.replaceChildren(...reachableAgents.slice(0, 4).map((agent) => {
    const row = document.createElement("div");
    row.className = "agent-row";
    const caps = agent.capabilities.slice(0, 3).map((capability) => `<span>${escapeHtml(capability)}</span>`).join("");
    row.innerHTML = `
      <div class="agent-row-head">
        <div>
          <strong>${escapeHtml(agent.type)}</strong>
          <small>${escapeHtml(agent.agentId)} on ${escapeHtml(agent.host)}</small>
        </div>
        <span class="dot ${escapeHtml(agent.status)}"></span>
      </div>
      <small>${escapeHtml(agent.contact)}</small>
      <div class="agent-caps">${caps}</div>
    `;
    return row;
  }));
}

function render(time) {
  resizeCanvas(meshCanvas, meshCtx);
  resizeCanvas(document.querySelector("#spotlightChart"), spotlightChart);
  resizeCanvas(document.querySelector("#throughputChart"), throughputChart);
  resizeCanvas(document.querySelector("#routerChart"), routerChart);
  resizeCanvas(document.querySelector("#deviceChart"), deviceChart);
  const width = meshCanvas.clientWidth;
  const height = meshCanvas.clientHeight;
  const screenMode = getScreenMode({ width, height });
  applyScreenMode(screenMode);
  const hosts = appState.liveHosts ?? createTelemetrySnapshot(time);
  const topHost = getTopActiveHost(hosts);
  const localNetwork = summarizeLocalNetwork(hosts);
  renderState.hosts = hosts;
  renderState.topHost = topHost;
  renderState.width = width;
  renderState.height = height;

  meshCtx.clearRect(0, 0, width, height);
  drawFlows(meshCtx, hosts, topHost, time, width, height);
  hosts.forEach((host) => drawNode(meshCtx, host, topHost, renderState.hoveredHost, screenMode, time, width, height));

  const wave = Array.from({ length: 48 }, (_, index) => 0.36 + Math.sin(time / 520 + index * 0.34) * 0.19 + Math.sin(time / 980 + index * 0.8) * 0.1);
  const disk = Array.from({ length: 48 }, (_, index) => 0.28 + Math.sin(time / 700 + index * 0.5) * 0.14);
  const routerBase = Math.max(0.05, Math.min(0.95, (localNetwork.router?.throughputMbps ?? 0) / Math.max(localNetwork.throughputMbps, 1)));
  const deviceBase = Math.max(0.08, Math.min(0.86, (localNetwork.router?.devicesConnected ?? hosts.length) / 80));
  drawChart(spotlightChart, wave.map((v, i) => Math.max(0.08, Math.min(0.94, v + disk[i]))), "#ffae3d", "rgba(255,174,61,0.16)", spotlightChart.canvas.clientWidth, spotlightChart.canvas.clientHeight);
  drawChart(throughputChart, wave.map((v) => Math.max(0.08, Math.min(0.92, v + 0.2))), "#37d7ff", "rgba(55,215,255,0.15)", throughputChart.canvas.clientWidth, throughputChart.canvas.clientHeight);
  drawChart(routerChart, wave.map((v, i) => Math.max(0.04, Math.min(0.96, routerBase + v * 0.35 + disk[i] * 0.12))), "#2dd4bf", "rgba(45,212,191,0.14)", routerChart.canvas.clientWidth, routerChart.canvas.clientHeight);
  drawChart(deviceChart, wave.map((v) => Math.max(0.05, Math.min(0.95, deviceBase + v * 0.18))), "#a778ff", "rgba(167,120,255,0.16)", deviceChart.canvas.clientWidth, deviceChart.canvas.clientHeight);
  updateDom(hosts, topHost, time);

  requestAnimationFrame(render);
}

requestAnimationFrame(render);
pollLiveTelemetry();
setInterval(pollLiveTelemetry, 5000);

meshCanvas.addEventListener("mousemove", (event) => {
  const host = hitTestHost(event.clientX, event.clientY);
  renderState.hoveredHost = host;
  meshCanvas.style.cursor = host ? "crosshair" : "default";
  if (host) positionTooltip(host, event.clientX, event.clientY);
  else nodeTooltip.classList.remove("visible");
});

meshCanvas.addEventListener("mouseleave", () => {
  renderState.hoveredHost = null;
  meshCanvas.style.cursor = "default";
  nodeTooltip.classList.remove("visible");
});
