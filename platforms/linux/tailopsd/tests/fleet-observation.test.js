import assert from "node:assert/strict";
import test from "node:test";

import { buildFleetObservation } from "../src/fleet-observation.js";

const status = {
  Self: {
    ID: "self",
    HostName: "arm-worker",
    DNSName: "arm-worker.example.test.",
    OS: "linux",
    Online: true,
    Active: true,
    TailscaleIPs: ["100.64.0.10"],
  },
  Peer: {
    laptop: {
      ID: "laptop",
      HostName: "laptop",
      DNSName: "laptop.example.test.",
      OS: "macOS",
      Online: false,
      TailscaleIPs: ["100.64.0.11"],
    },
    provider: {
      ID: "provider",
      HostName: "provider-node",
      OS: "linux",
      Online: true,
      Tags: ["tag:mullvad-exit-node"],
      TailscaleIPs: ["100.64.0.12"],
    },
  },
};

test("managed-fleet observations exclude provider nodes by default", () => {
  const observation = buildFleetObservation(status, {
    observedAt: "2026-08-29T14:00:00.000Z",
  });

  assert.equal(observation.kind, "tailops.fleet-observation");
  assert.equal(observation.schemaVersion, 1);
  assert.equal(observation.collector.node, "arm-worker");
  assert.equal(observation.policy, "managed-fleet");
  assert.deepEqual(observation.nodes.map((node) => node.name), ["arm-worker", "laptop"]);
  assert.deepEqual(observation.summary, {
    nodeCount: 2,
    onlineCount: 1,
    offlineCount: 1,
    providerNodesExcluded: 1,
  });
});

test("all-peers observations preserve provider nodes for diagnostics", () => {
  const observation = buildFleetObservation(status, { includeProviderNodes: true });

  assert.equal(observation.policy, "all-peers");
  assert.equal(observation.summary.nodeCount, 3);
  assert.equal(observation.summary.providerNodesExcluded, 0);
  assert.equal(observation.nodes.at(-1).classification, "provider");
});
