import { execFile } from "node:child_process";
import { readdir, readFile, statfs } from "node:fs/promises";
import os from "node:os";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

// Thresholds for the warnings a Fleet reader acts on; raw values are always reported too.
export const DISK_WARNING_USED_RATIO = 0.9;
export const MEMORY_WARNING_AVAILABLE_RATIO = 0.1;
export const TEMPERATURE_WARNING_CELSIUS = 80;

export function parseMeminfo(text) {
  const kilobytes = (key) => {
    const match = new RegExp(`^${key}:\\s+(\\d+)\\s+kB$`, "m").exec(text);
    return match ? Number(match[1]) * 1024 : null;
  };
  const totalBytes = kilobytes("MemTotal");
  const availableBytes = kilobytes("MemAvailable");
  return totalBytes === null || availableBytes === null ? null : { totalBytes, availableBytes };
}

export function parseOSRelease(text) {
  const match = /^PRETTY_NAME=(.*)$/m.exec(text);
  return match ? match[1].trim().replace(/^"(.*)"$/, "$1") : null;
}

export function parseFailedUnits(text) {
  return text
    .split("\n")
    .map((line) => line.trim().split(/\s+/)[0])
    .filter((unit) => unit && unit.includes("."))
    .sort();
}

async function readDisk(mount, { statFilesystem = statfs } = {}) {
  const stats = await statFilesystem(mount);
  return {
    mount,
    totalBytes: stats.blocks * stats.bsize,
    availableBytes: stats.bavail * stats.bsize,
  };
}

async function readMaximumTemperature({ listDirectory = readdir, read = readFile } = {}) {
  const zones = (await listDirectory("/sys/class/thermal")).filter((name) => name.startsWith("thermal_zone"));
  const readings = await Promise.all(zones.map(async (zone) => {
    const milliCelsius = Number.parseInt(await read(`/sys/class/thermal/${zone}/temp`, "utf8"), 10);
    return Number.isFinite(milliCelsius) ? milliCelsius / 1000 : null;
  }));
  const valid = readings.filter((value) => value !== null && value > -40 && value < 150);
  return valid.length ? Math.max(...valid) : null;
}

async function readFailedUnits({ run = execFileAsync } = {}) {
  const { stdout } = await run(
    "systemctl",
    ["list-units", "--state=failed", "--no-legend", "--plain", "--no-pager"],
    { encoding: "utf8", timeout: 5_000, maxBuffer: 256 * 1024, windowsHide: true },
  );
  return parseFailedUnits(stdout);
}

export function healthWarnings(host) {
  const warnings = [];
  for (const disk of host.disks ?? []) {
    if (disk.totalBytes > 0 && 1 - disk.availableBytes / disk.totalBytes >= DISK_WARNING_USED_RATIO) {
      warnings.push(`disk ${disk.mount} is ${Math.round((1 - disk.availableBytes / disk.totalBytes) * 100)}% full`);
    }
  }
  if (host.memory && host.memory.availableBytes / host.memory.totalBytes <= MEMORY_WARNING_AVAILABLE_RATIO) {
    warnings.push(`memory is ${Math.round((host.memory.availableBytes / host.memory.totalBytes) * 100)}% available`);
  }
  if (host.failedUnits?.length) {
    warnings.push(`${host.failedUnits.length} failed systemd unit${host.failedUnits.length === 1 ? "" : "s"}`);
  }
  if (host.temperatureCelsius !== null && host.temperatureCelsius >= TEMPERATURE_WARNING_CELSIUS) {
    warnings.push(`hottest sensor at ${Math.round(host.temperatureCelsius)} °C`);
  }
  return warnings;
}

/**
 * Read-only health of the collector node itself. Every probe is independent: a probe
 * that fails reports null and a probe error instead of failing the snapshot.
 */
export async function collectHostHealth({
  read = readFile,
  listDirectory = readdir,
  statFilesystem = statfs,
  run = execFileAsync,
  system = os,
  mounts = ["/"],
} = {}) {
  const probeErrors = [];
  const probe = async (name, action) => {
    try {
      return await action();
    } catch {
      probeErrors.push(name);
      return null;
    }
  };

  const [osName, memory, disks, failedUnits, temperatureCelsius] = await Promise.all([
    probe("os-release", async () => parseOSRelease(await read("/etc/os-release", "utf8"))),
    probe("meminfo", async () => parseMeminfo(await read("/proc/meminfo", "utf8"))),
    probe("disk", async () => Promise.all(mounts.map((mount) => readDisk(mount, { statFilesystem })))),
    probe("systemd-failed-units", async () => readFailedUnits({ run })),
    probe("thermal", async () => readMaximumTemperature({ listDirectory, read })),
  ]);

  const host = {
    hostname: system.hostname(),
    os: osName,
    kernel: system.release(),
    architecture: system.arch(),
    cpuCount: system.cpus().length,
    uptimeSeconds: Math.round(system.uptime()),
    loadAverage: system.loadavg().map((value) => Math.round(value * 100) / 100),
    memory,
    disks: disks ?? [],
    failedUnits,
    temperatureCelsius: temperatureCelsius === null ? null : Math.round(temperatureCelsius * 10) / 10,
    probeErrors: probeErrors.sort(),
  };
  return { ...host, warnings: healthWarnings(host) };
}
