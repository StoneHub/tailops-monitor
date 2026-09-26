import assert from "node:assert/strict";
import test from "node:test";

import { runCLI } from "../src/cli.js";

const status = {
  Self: {
    ID: "self",
    HostName: "arm-worker",
    OS: "linux",
    Online: true,
  },
  Peer: {},
};

test("snapshot writes one versioned JSON observation", async () => {
  let stdout = "";
  let stderr = "";

  const exitCode = await runCLI(["snapshot"], {
    collectStatus: async () => status,
    now: () => new Date("2026-08-29T14:00:00.000Z"),
    writeStdout: (value) => { stdout += value; },
    writeStderr: (value) => { stderr += value; },
  });

  assert.equal(exitCode, 0);
  assert.equal(stderr, "");
  assert.equal(JSON.parse(stdout).observedAt, "2026-08-29T14:00:00.000Z");
});

test("snapshot can atomically hand an observation to a persistence adapter", async () => {
  let receipt = "";
  let writtenPath = null;
  let writtenObservation = null;

  const exitCode = await runCLI(["snapshot", "--output", "/var/lib/tailopsd/fleet-observation.json"], {
    collectStatus: async () => status,
    now: () => new Date("2026-08-29T14:00:00.000Z"),
    writeObservation: async (path, observation) => {
      writtenPath = path;
      writtenObservation = observation;
    },
    writeStdout: (value) => { receipt += value; },
    writeStderr: () => {},
  });

  assert.equal(exitCode, 0);
  assert.equal(writtenPath, "/var/lib/tailopsd/fleet-observation.json");
  assert.equal(writtenObservation.kind, "tailops.fleet-observation");
  assert.equal(JSON.parse(receipt).status, "written");
});

test("doctor returns its readiness exit code", async () => {
  let stdout = "";

  const exitCode = await runCLI(["doctor"], {
    inspectRuntime: async () => ({ status: "blocked", kind: "tailops.runtime-doctor" }),
    writeStdout: (value) => { stdout += value; },
    writeStderr: () => {},
  });

  assert.equal(exitCode, 4);
  assert.equal(JSON.parse(stdout).status, "blocked");
});

test("version reports the package version without collecting status", async () => {
  let stdout = "";

  const exitCode = await runCLI(["version"], {
    collectStatus: async () => { throw new Error("must not run"); },
    writeStdout: (value) => { stdout += value; },
    writeStderr: () => {},
  });

  assert.equal(exitCode, 0);
  assert.equal(stdout, "tailopsd 0.1.0\n");
});

test("unknown options fail closed before collecting status", async () => {
  let collected = false;
  let stderr = "";

  const exitCode = await runCLI(["snapshot", "--execute-anything"], {
    collectStatus: async () => {
      collected = true;
      return status;
    },
    writeStdout: () => {},
    writeStderr: (value) => { stderr += value; },
  });

  assert.equal(exitCode, 2);
  assert.equal(collected, false);
  assert.match(stderr, /unknown option/);
});

test("collector failures return a bounded error", async () => {
  let stderr = "";

  const exitCode = await runCLI(["snapshot"], {
    collectStatus: async () => {
      throw new Error("Tailscale unavailable");
    },
    writeStdout: () => {},
    writeStderr: (value) => { stderr += value; },
  });

  assert.equal(exitCode, 3);
  assert.equal(stderr, "tailopsd: Tailscale unavailable\n");
});
