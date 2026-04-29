export function buildAgentDirectory(hosts) {
  return hosts.map((host) => ({
    host: host.name ?? host.id,
    hostId: host.id,
    status: host.status,
    tailscaleIp: host.tailscaleIp ?? null,
    magicDns: host.magicDns ?? null,
    agents: (host.agents ?? []).map((agent) => ({
      agentId: agent.id,
      type: agent.type,
      status: agent.status,
      contact: agent.endpoint,
      capabilities: [...(agent.capabilities ?? [])],
      lastSeen: agent.lastSeen,
    })),
  }));
}

export function getReachableAgents(directory) {
  return directory.flatMap((entry) =>
    entry.agents
      .filter((agent) => agent.status === "available")
      .map((agent) => ({
        host: entry.host,
        hostId: entry.hostId,
        tailscaleIp: entry.tailscaleIp,
        magicDns: entry.magicDns,
        agentId: agent.agentId,
        type: agent.type,
        contact: agent.contact,
        capabilities: agent.capabilities,
        lastSeen: agent.lastSeen,
      })),
  );
}

export function serializeAgentDirectory(directory) {
  return JSON.stringify(
    {
      schema: "tailops.agent-directory.v1",
      generatedAt: new Date(0).toISOString(),
      hosts: directory,
    },
    null,
    2,
  );
}

export const sampleAgentHosts = [
  {
    id: "atlas-win11",
    name: "atlas-win11",
    tailscaleIp: "100.84.20.11",
    magicDns: "atlas-win11.tailnet.ts.net",
    status: "online",
    agents: [
      {
        id: "desktop-helper",
        type: "local worker",
        status: "available",
        endpoint: "http://atlas-win11.tailnet.ts.net:8787/agent",
        capabilities: ["browser", "desktop", "windows"],
        lastSeen: "2026-04-29T14:10:15-04:00",
      },
    ],
  },
  {
    id: "nuc-lab",
    name: "nuc-lab",
    tailscaleIp: "100.85.10.21",
    magicDns: "nuc-lab.tailnet.ts.net",
    status: "online",
    agents: [
      {
        id: "lab-mcp",
        type: "MCP",
        status: "available",
        endpoint: "https://nuc-lab.tailnet.ts.net/mcp",
        capabilities: ["shell", "git", "builds", "containers"],
        lastSeen: "2026-04-29T14:12:01-04:00",
      },
    ],
  },
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
        capabilities: ["files", "storage", "indexing", "retrieval"],
        lastSeen: "2026-04-29T14:12:30-04:00",
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
        capabilities: ["video", "transcode", "media"],
        lastSeen: "2026-04-29T14:11:02-04:00",
      },
    ],
  },
  {
    id: "work-laptop",
    name: "work-laptop",
    tailscaleIp: "100.77.8.19",
    magicDns: "work-laptop.tailnet.ts.net",
    status: "warning",
    agents: [
      {
        id: "laptop-codex",
        type: "OpenClaw",
        status: "unknown",
        endpoint: "http://work-laptop.tailnet.ts.net:3920/mcp",
        capabilities: ["coding", "files"],
        lastSeen: "2026-04-29T13:59:42-04:00",
      },
    ],
  },
  {
    id: "homelab-router",
    name: "homelab-router",
    tailscaleIp: "100.100.1.1",
    magicDns: "homelab-router.tailnet.ts.net",
    status: "online",
    agents: [],
  },
];
