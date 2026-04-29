import test from "node:test";
import assert from "node:assert/strict";
import {
  calculateActivityScore,
  getTopActiveHost,
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
