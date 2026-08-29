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
