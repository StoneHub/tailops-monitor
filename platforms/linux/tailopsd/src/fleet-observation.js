export const MULLVAD_PROVIDER_TAG = "tag:mullvad-exit-node";

function tagsFor(peer) {
  return Array.isArray(peer?.Tags)
    ? peer.Tags.filter((tag) => typeof tag === "string").sort()
    : [];
}

function stripTrailingDot(value) {
  return typeof value === "string" ? value.replace(/\.$/, "") : "";
}

function peerID(peer, index) {
  return peer.ID || peer.PublicKey || peer.DNSName || peer.HostName || `tailnet-node-${index}`;
}

function peerName(peer, id) {
  const dnsName = stripTrailingDot(peer.DNSName);
  if (peer.HostName && peer.HostName.toLowerCase() !== "localhost") return peer.HostName;
  if (dnsName) return dnsName.split(".")[0];
  return id;
}

function isProviderNode(peer) {
  return tagsFor(peer).includes(MULLVAD_PROVIDER_TAG);
}

function normalizePeer(peer, index) {
  const id = peerID(peer, index);
  const providerNode = isProviderNode(peer);

  return {
    id,
    name: peerName(peer, id),
    classification: providerNode ? "provider" : "fleet",
    os: peer.OS ?? "unknown",
    status: peer.Online ? "online" : "offline",
    tailscaleIPs: Array.isArray(peer.TailscaleIPs) ? peer.TailscaleIPs : [],
    magicDNS: stripTrailingDot(peer.DNSName) || null,
    tags: tagsFor(peer),
    active: Boolean(peer.Active),
    exitNode: Boolean(peer.ExitNode || peer.ExitNodeOption),
  };
}

function collectorName(status) {
  const self = status?.Self;
  if (!self) return "unknown";
  return peerName(self, peerID(self, 0));
}

export function buildFleetObservation(
  status,
  { includeProviderNodes = false, observedAt = new Date().toISOString() } = {},
) {
  if (!status || typeof status !== "object" || Array.isArray(status)) {
    throw new TypeError("Tailscale status must be an object");
  }

  const rawPeers = [status.Self, ...Object.values(status.Peer ?? {})].filter(Boolean);
  const normalizedPeers = rawPeers.map(normalizePeer);
  const providerNodes = normalizedPeers.filter((peer) => peer.classification === "provider");
  const nodes = includeProviderNodes
    ? normalizedPeers
    : normalizedPeers.filter((peer) => peer.classification === "fleet");

  return {
    schemaVersion: 1,
    kind: "tailops.fleet-observation",
    observedAt,
    collector: {
      node: collectorName(status),
      source: "tailscale-local-cli",
    },
    policy: includeProviderNodes ? "all-peers" : "managed-fleet",
    summary: {
      nodeCount: nodes.length,
      onlineCount: nodes.filter((peer) => peer.status === "online").length,
      offlineCount: nodes.filter((peer) => peer.status === "offline").length,
      providerNodesExcluded: includeProviderNodes ? 0 : providerNodes.length,
    },
    nodes,
  };
}
