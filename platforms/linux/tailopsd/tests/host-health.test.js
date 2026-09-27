import assert from "node:assert/strict";
import test from "node:test";

import {
  collectHostHealth,
  healthWarnings,
  parseFailedUnits,
  parseMeminfo,
  parseOSRelease,
} from "../src/host-health.js";
import { runCLI } from "../src/cli.js";

const GiB = 1024 ** 3;

const system = {
  hostname: () => "arm-worker",
  release: () => "6.1.118",
  arch: () => "arm64",
  cpus: () => new Array(8).fill({}),
  uptime: () => 3600.4,
  loadavg: () => [0.123, 0.456, 0.789],
};

const files = {
  "/etc/os-release": 'NAME="Ubuntu"\nPRETTY_NAME="Ubuntu 24.04.5 LTS"\n',
  "/proc/meminfo": "MemTotal:       16334356 kB\nMemFree:  1000 kB\nMemAvailable:   10677896 kB\n",
  "/sys/class/thermal/thermal_zone0/temp": "37000\n",
  "/sys/class/thermal/thermal_zone1/temp": "41500\n",
};

function readers(overrides = {}) {
  return {
    system,
    read: async (path) => {
      if (!(path in files)) throw new Error(`missing ${path}`);
      return files[path];
    },
    listDirectory: async () => ["cooling_device0", "thermal_zone0", "thermal_zone1"],
    statFilesystem: async () => ({ blocks: 100, bavail: 60, bsize: GiB / 100 }),
    run: async () => ({ stdout: "" }),
    ...overrides,
  };
}

test("parsers read os-release, meminfo, and failed units", () => {
  assert.equal(parseOSRelease('PRETTY_NAME="Ubuntu 24.04.5 LTS"\n'), "Ubuntu 24.04.5 LTS");
  assert.deepEqual(parseMeminfo(files["/proc/meminfo"]), {
    totalBytes: 16334356 * 1024,
    availableBytes: 10677896 * 1024,
  });
  assert.equal(parseMeminfo("MemTotal: 1 kB\n"), null);
  assert.deepEqual(
    parseFailedUnits("rooms.service loaded failed failed Rooms\nbackup.timer loaded failed failed Backup\n\n"),
    ["backup.timer", "rooms.service"],
  );
});

test("healthy host reports raw values and no warnings", async () => {
  const host = await collectHostHealth(readers());

  assert.equal(host.hostname, "arm-worker");
  assert.equal(host.os, "Ubuntu 24.04.5 LTS");
  assert.equal(host.cpuCount, 8);
  assert.equal(host.uptimeSeconds, 3600);
  assert.deepEqual(host.loadAverage, [0.12, 0.46, 0.79]);
  assert.deepEqual(host.disks, [{ mount: "/", totalBytes: GiB, availableBytes: 0.6 * GiB }]);
  assert.deepEqual(host.failedUnits, []);
  assert.equal(host.temperatureCelsius, 41.5);
  assert.deepEqual(host.probeErrors, []);
  assert.deepEqual(host.warnings, []);
});

test("full disk, low memory, failed units, and heat become warnings", () => {
  const warnings = healthWarnings({
    disks: [{ mount: "/", totalBytes: 100, availableBytes: 5 }],
    memory: { totalBytes: 100, availableBytes: 8 },
    failedUnits: ["rooms.service"],
    temperatureCelsius: 85,
  });

  assert.deepEqual(warnings, [
    "disk / is 95% full",
    "memory is 8% available",
    "1 failed systemd unit",
    "hottest sensor at 85 °C",
  ]);
});

test("a failing probe is reported without failing the others", async () => {
  const host = await collectHostHealth(readers({
    run: async () => { throw new Error("systemctl unavailable"); },
    listDirectory: async () => { throw new Error("no thermal"); },
  }));

  assert.equal(host.failedUnits, null);
  assert.equal(host.temperatureCelsius, null);
  assert.deepEqual(host.probeErrors, ["systemd-failed-units", "thermal"]);
  assert.equal(host.os, "Ubuntu 24.04.5 LTS");
});

test("snapshot includes host health unless --no-host is passed", async () => {
  const status = { Self: { ID: "self", HostName: "arm-worker", Online: true }, Peer: {} };
  const host = { hostname: "arm-worker", warnings: ["1 failed systemd unit"] };
  let stdout = "";
  const options = {
    collectStatus: async () => status,
    collectHost: async () => host,
    writeStdout: (value) => { stdout += value; },
    writeStderr: () => {},
  };

  assert.equal(await runCLI(["snapshot"], options), 0);
  assert.deepEqual(JSON.parse(stdout).host, host);

  stdout = "";
  assert.equal(await runCLI(["snapshot", "--no-host"], {
    ...options,
    collectHost: async () => { throw new Error("must not be called"); },
  }), 0);
  assert.equal("host" in JSON.parse(stdout), false);
});

test("--health-output writes a readable health-only document without peers", async () => {
  const status = {
    Self: { ID: "self", HostName: "fcfdev", Online: true, TailscaleIPs: ["100.64.0.1"] },
    Peer: { a: { ID: "a", HostName: "laptop", Online: false, TailscaleIPs: ["100.64.0.2"] } },
  };
  const host = { hostname: "fcfdev", warnings: [] };
  const writes = [];

  const exitCode = await runCLI(
    ["snapshot", "--output", "/var/lib/tailopsd/fleet-observation.json", "--health-output", "/var/lib/tailopsd/host-health.json"],
    {
      collectStatus: async () => status,
      collectHost: async () => host,
      now: () => new Date("2026-09-26T22:00:00.000Z"),
      writeObservation: async (path, document, options) => { writes.push({ path, document, options }); },
      writeStdout: () => {},
      writeStderr: () => {},
    },
  );

  assert.equal(exitCode, 0);
  const health = writes.find((write) => write.path.endsWith("host-health.json"));
  assert.equal(health.options.mode, 0o644);
  assert.equal(health.document.kind, "tailops.host-health");
  assert.deepEqual(health.document.host, host);
  assert.equal(health.document.summary.nodeCount, 2);
  assert.equal(JSON.stringify(health.document).includes("100.64.0"), false);
  assert.equal("nodes" in health.document, false);

  const full = writes.find((write) => write.path.endsWith("fleet-observation.json"));
  assert.equal(full.options, undefined);
});

test("--health-output refuses --no-host", async () => {
  let stderr = "";
  const exitCode = await runCLI(["snapshot", "--no-host", "--health-output", "/tmp/h.json"], {
    collectStatus: async () => ({ Self: { ID: "s" } }),
    writeStdout: () => {},
    writeStderr: (value) => { stderr += value; },
  });
  assert.equal(exitCode, 2);
  assert.match(stderr, /needs host health/);
});
