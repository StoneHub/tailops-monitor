import test from "node:test";
import assert from "node:assert/strict";
import {
  buildAgentDirectory,
  getReachableAgents,
  serializeAgentDirectory,
} from "../src/agents.js";

const hosts = [
  {
    id: "nas-vault",
    name: "nas-vault",
    tailscaleIp: "100.88.12.42",
    magicDns: "nas-vault.tailnet.ts.net",
    status: "online",
    agents: [
      {
        id: "openclaw-nas",
        type: "OpenClaw",
        status: "available",
        endpoint: "http://nas-vault.tailnet.ts.net:4317/mcp",
        capabilities: ["files", "storage", "indexing"],
        lastSeen: "2026-04-29T14:12:30-04:00",
      },
    ],
  },
  {
    id: "media-mac",
    name: "media-mac",
    tailscaleIp: "100.91.44.18",
    magicDns: "media-mac.tailnet.ts.net",
    status: "online",
    agents: [
      {
        id: "render-worker",
        type: "local worker",
        status: "busy",
        endpoint: "ws://media-mac.tailnet.ts.net:8787/agent",
        capabilities: ["video", "transcode"],
        lastSeen: "2026-04-29T14:11:02-04:00",
      },
    ],
  },
  {
    id: "pi-dns",
    name: "pi-dns",
    tailscaleIp: "100.64.0.53",
    magicDns: "pi-dns.tailnet.ts.net",
    status: "online",
    agents: [],
  },
];

test("buildAgentDirectory produces a phonebook entry for every host", () => {
  const directory = buildAgentDirectory(hosts);

  assert.equal(directory.length, 3);
  assert.deepEqual(directory.map((entry) => entry.host), ["nas-vault", "media-mac", "pi-dns"]);
  assert.equal(directory[0].agents[0].contact, "http://nas-vault.tailnet.ts.net:4317/mcp");
  assert.equal(directory[2].agents.length, 0);
});

test("getReachableAgents only returns available agents", () => {
  const available = getReachableAgents(buildAgentDirectory(hosts));

  assert.equal(available.length, 1);
  assert.equal(available[0].agentId, "openclaw-nas");
  assert.equal(available[0].host, "nas-vault");
});

test("serializeAgentDirectory returns stable JSON for /api/agents style delivery", () => {
  const json = serializeAgentDirectory(buildAgentDirectory(hosts));
  const parsed = JSON.parse(json);

  assert.equal(parsed.schema, "tailops.agent-directory.v1");
  assert.equal(parsed.hosts.length, 3);
  assert.equal(parsed.hosts[0].agents[0].capabilities.includes("files"), true);
});
