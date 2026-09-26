import assert from "node:assert/strict";
import test from "node:test";

import { inspectLinuxRuntime } from "../src/runtime-doctor.js";

test("doctor marks the CLI and systemd timer ready when requirements pass", async () => {
  const report = await inspectLinuxRuntime({
    platform: "linux",
    architecture: "x64",
    nodeVersion: "22.23.2",
    collectStatus: async () => ({ Self: {} }),
    checkSystemd: async () => true,
    observedAt: "2026-08-29T14:00:00.000Z",
  });

  assert.equal(report.status, "ready");
  assert.deepEqual(report.profiles, { cli: "ready", systemdTimer: "ready" });
});

test("doctor fails closed when the local Tailscale status is unavailable", async () => {
  const report = await inspectLinuxRuntime({
    platform: "linux",
    architecture: "arm64",
    nodeVersion: "22.23.2",
    collectStatus: async () => { throw new Error("unavailable"); },
    checkSystemd: async () => true,
  });

  assert.equal(report.status, "blocked");
  assert.equal(report.profiles.cli, "blocked");
  assert.equal(report.checks.find((check) => check.id === "tailscale-status").status, "fail");
});

test("doctor keeps non-systemd Linux usable as a CLI", async () => {
  const report = await inspectLinuxRuntime({
    platform: "linux",
    architecture: "x64",
    nodeVersion: "20.0.0",
    collectStatus: async () => ({ Self: {} }),
    checkSystemd: async () => false,
  });

  assert.equal(report.status, "ready");
  assert.deepEqual(report.profiles, { cli: "ready", systemdTimer: "blocked" });
});
