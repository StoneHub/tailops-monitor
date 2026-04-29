import test from "node:test";
import assert from "node:assert/strict";
import {
  calculateActivityScore,
  getTopActiveHost,
  mapTailscaleStatusToHosts,
  normalizeCpuTemperature,
} from "../src/telemetry.js";

const hosts = [
  {
    id: "pi-dns",
    status: "online",
    cpu: 16,
    memory: 35,
    diskIoMbps: 12,
    networkInMbps: 24,
    networkOutMbps: 18,
    latencyMs: 2.1,
    packetLossPct: 0,
    cpuTempC: 47,
    activeServices: 3,
  },
  {
    id: "nas-vault",
    status: "online",
    cpu: 82,
    memory: 64,
    diskIoMbps: 1280,
    networkInMbps: 4500,
    networkOutMbps: 8200,
    latencyMs: 0.8,
    packetLossPct: 0.02,
    cpuTempC: 71,
    activeServices: 12,
  },
  {
    id: "work-laptop",
    status: "online",
    cpu: 52,
    memory: 70,
    diskIoMbps: 140,
    networkInMbps: 260,
    networkOutMbps: 110,
    latencyMs: 7.5,
    packetLossPct: 0.1,
    cpuTempC: 86,
    activeServices: 5,
  },
];

test("calculateActivityScore heavily weights network and disk activity", () => {
  const nas = calculateActivityScore(hosts[1]);
  const laptop = calculateActivityScore(hosts[2]);
  const pi = calculateActivityScore(hosts[0]);

  assert.ok(nas > laptop, `expected nas-vault to outrank work-laptop, got ${nas} <= ${laptop}`);
  assert.ok(laptop > pi, `expected work-laptop to outrank pi-dns, got ${laptop} <= ${pi}`);
});

test("getTopActiveHost returns the highest activity host with reason labels", () => {
  const top = getTopActiveHost(hosts);

  assert.equal(top.id, "nas-vault");
  assert.equal(top.reason, "High network + disk IO");
  assert.ok(top.score > 90);
});

test("normalizeCpuTemperature maps host temperature into thermal state", () => {
  assert.deepEqual(normalizeCpuTemperature(47), { level: "cool", normalized: 39 });
  assert.deepEqual(normalizeCpuTemperature(71), { level: "warm", normalized: 64 });
  assert.deepEqual(normalizeCpuTemperature(86), { level: "hot", normalized: 81 });
});

test("mapTailscaleStatusToHosts converts real status json into dashboard hosts", () => {
  const status = {
    Self: {
      ID: "self-id",
      HostName: "StoneBook",
      DNSName: "stonebook.example.ts.net.",
      OS: "windows",
      TailscaleIPs: ["100.72.170.9"],
      AllowedIPs: ["100.72.170.9/32"],
      RxBytes: 10_000,
      TxBytes: 20_000,
      Online: true,
      Active: false,
      Relay: "iad",
      ExitNode: false,
      ExitNodeOption: false,
      LastHandshake: "2026-04-29T10:07:39.5559079-04:00",
    },
    Peer: {
      "nodekey:abc": {
        ID: "peer-id",
        HostName: "CR10sPi",
        DNSName: "cr10spi.example.ts.net.",
        OS: "linux",
        TailscaleIPs: ["100.116.136.57"],
        AllowedIPs: ["100.116.136.57/32", "192.168.1.0/24"],
        RxBytes: 9_718_648,
        TxBytes: 523_456,
        Online: true,
        Active: true,
        Relay: "mia",
        ExitNode: false,
        ExitNodeOption: false,
        LastHandshake: "2026-04-29T10:07:39.5559079-04:00",
      },
      "nodekey:def": {
        ID: "offline-id",
        HostName: "pixel",
        DNSName: "pixel.example.ts.net.",
        OS: "android",
        TailscaleIPs: ["100.83.152.74"],
        AllowedIPs: ["100.83.152.74/32"],
        RxBytes: 0,
        TxBytes: 0,
        Online: false,
        Active: false,
        Relay: "iad",
        ExitNode: false,
        ExitNodeOption: false,
      },
    },
  };

  const hosts = mapTailscaleStatusToHosts(status, {
    localMetrics: { cpu: 21, memory: 58, cpuTempC: null },
    ratesById: new Map([
      ["self-id", { networkInMbps: 1.5, networkOutMbps: 2.5 }],
      ["peer-id", { networkInMbps: 8.5, networkOutMbps: 4.25 }],
    ]),
  });

  assert.equal(hosts.length, 3);
  assert.equal(hosts[0].name, "StoneBook");
  assert.equal(hosts[0].latencyMs, 0);
  assert.equal(hosts[0].cpu, 21);
  assert.equal(hosts[0].memory, 58);
  assert.equal(hosts[1].name, "CR10sPi");
  assert.equal(hosts[1].status, "online");
  assert.equal(hosts[1].subnetRoutes, true);
  assert.equal(hosts[1].networkInMbps, 8.5);
  assert.equal(hosts[2].status, "offline");
  assert.equal(hosts[2].latencyMs, null);
  assert.ok(hosts[1].x > 0 && hosts[1].x < 1);
});

test("mapTailscaleStatusToHosts uses MagicDNS basename when host reports localhost", () => {
  const hosts = mapTailscaleStatusToHosts({
    Peer: {
      "nodekey:phone": {
        ID: "phone-id",
        HostName: "localhost",
        DNSName: "pixel-6a.example.ts.net.",
        OS: "android",
        TailscaleIPs: ["100.83.152.74"],
        AllowedIPs: ["100.83.152.74/32"],
        Online: false,
      },
    },
  });

  assert.equal(hosts[0].name, "pixel-6a");
});
