import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

function nodeMajor(version) {
  return Number.parseInt(String(version).split(".")[0], 10);
}

export async function probeSystemd({ run = execFileAsync } = {}) {
  try {
    await run("systemctl", ["show", "--property=Version", "--value"], {
      encoding: "utf8",
      timeout: 5_000,
      maxBuffer: 64 * 1024,
      windowsHide: true,
    });
    return true;
  } catch {
    return false;
  }
}

export async function inspectLinuxRuntime({
  platform = process.platform,
  architecture = process.arch,
  nodeVersion = process.versions.node,
  collectStatus,
  checkSystemd = probeSystemd,
  observedAt = new Date().toISOString(),
}) {
  const checks = [];
  const linuxReady = platform === "linux";
  checks.push({
    id: "linux",
    status: linuxReady ? "pass" : "fail",
    observed: platform,
  });

  const nodeReady = Number.isFinite(nodeMajor(nodeVersion)) && nodeMajor(nodeVersion) >= 20;
  checks.push({
    id: "node",
    status: nodeReady ? "pass" : "fail",
    observed: nodeVersion,
    required: ">=20",
  });

  let tailscaleReady = false;
  if (linuxReady) {
    try {
      await collectStatus();
      tailscaleReady = true;
    } catch {
      tailscaleReady = false;
    }
  }
  checks.push({
    id: "tailscale-status",
    status: tailscaleReady ? "pass" : "fail",
  });

  const systemdReady = linuxReady ? await checkSystemd() : false;
  checks.push({
    id: "systemd",
    status: systemdReady ? "pass" : "unavailable",
    requiredFor: "systemd-timer",
  });

  const cliReady = linuxReady && nodeReady && tailscaleReady;

  return {
    schemaVersion: 1,
    kind: "tailops.runtime-doctor",
    observedAt,
    status: cliReady ? "ready" : "blocked",
    runtime: {
      platform,
      architecture,
      nodeVersion,
    },
    profiles: {
      cli: cliReady ? "ready" : "blocked",
      systemdTimer: cliReady && systemdReady ? "ready" : "blocked",
    },
    checks,
  };
}
