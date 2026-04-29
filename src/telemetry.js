const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

export function normalizeCpuTemperature(tempC) {
  let normalized = Math.floor(clamp(((tempC - 10) / 94) * 100, 0, 100));
  if (tempC >= 82) normalized = clamp(normalized + 1, 0, 100);
  let level = "cool";
  if (tempC >= 82) level = "hot";
  else if (tempC >= 62) level = "warm";
  return { level, normalized };
}

export function calculateActivityScore(host) {
  if (!host || host.status !== "online") return 0;

  const networkTotal = (host.networkInMbps ?? 0) + (host.networkOutMbps ?? 0);
  const networkScore = clamp(networkTotal / 120, 0, 100);
  const diskScore = clamp((host.diskIoMbps ?? 0) / 16, 0, 100);
  const cpuScore = clamp(host.cpu ?? 0, 0, 100);
  const memoryScore = clamp(host.memory ?? 0, 0, 100);
  const servicesScore = clamp((host.activeServices ?? 0) * 5, 0, 100);
  const latencyPenalty = clamp((host.latencyMs ?? 0) * 1.5, 0, 20);
  const packetPenalty = clamp((host.packetLossPct ?? 0) * 20, 0, 20);

  const weighted =
    networkScore * 0.42 +
    diskScore * 0.27 +
    cpuScore * 0.15 +
    memoryScore * 0.08 +
    servicesScore * 0.08 -
    latencyPenalty -
    packetPenalty + 12;

  return Math.round(clamp(weighted, 0, 100));
}

export function getActivityReason(host) {
  const networkTotal = (host.networkInMbps ?? 0) + (host.networkOutMbps ?? 0);
  if (networkTotal >= 1000 && (host.diskIoMbps ?? 0) >= 400) return "High network + disk IO";
  if (networkTotal >= 1000) return "High network throughput";
  if ((host.diskIoMbps ?? 0) >= 400) return "High disk IO";
  if ((host.cpu ?? 0) >= 75) return "High CPU load";
  if ((host.cpuTempC ?? 0) >= 82) return "High CPU temperature";
  return "Normal activity";
}

export function getTopActiveHost(hosts) {
  const ranked = hosts
    .map((host) => ({ ...host, score: calculateActivityScore(host), reason: getActivityReason(host) }))
    .sort((a, b) => b.score - a.score);
  return ranked[0] ?? null;
}

export function formatMbps(value) {
  if (value >= 1000) return `${(value / 1000).toFixed(1)} Gbps`;
  return `${Math.round(value)} Mbps`;
}

export function createTelemetrySnapshot(seed = 0) {
  const wobble = (base, amp, phase) => Math.round(base + Math.sin(seed / 900 + phase) * amp);
  return [
    {
      id: "atlas-win11",
      name: "atlas-win11",
      role: "Desktop",
      status: "online",
      x: 0.27,
      y: 0.66,
      cpu: wobble(34, 10, 0.2),
      memory: wobble(48, 8, 1.4),
      disk: 62,
      diskIoMbps: wobble(110, 40, 2.1),
      networkInMbps: wobble(340, 90, 0.8),
      networkOutMbps: wobble(190, 60, 1.9),
      latencyMs: 2.6,
      packetLossPct: 0.01,
      cpuTempC: wobble(58, 5, 0.7),
      uptime: "6d 4h",
      exitNode: false,
      subnetRoutes: false,
      activeServices: 6,
      tags: ["desktop", "windows"],
    },
    {
      id: "nuc-lab",
      name: "nuc-lab",
      role: "Lab Compute",
      status: "online",
      x: 0.38,
      y: 0.38,
      cpu: wobble(46, 14, 1.1),
      memory: wobble(57, 9, 2.0),
      disk: 71,
      diskIoMbps: wobble(260, 95, 2.8),
      networkInMbps: wobble(620, 160, 0.4),
      networkOutMbps: wobble(480, 140, 1.6),
      latencyMs: 1.4,
      packetLossPct: 0,
      cpuTempC: wobble(64, 7, 2.7),
      uptime: "18d 7h",
      exitNode: false,
      subnetRoutes: true,
      activeServices: 9,
      tags: ["lab", "linux"],
    },
    {
      id: "nas-vault",
      name: "nas-vault",
      role: "Storage + Agents",
      status: "online",
      x: 0.63,
      y: 0.49,
      cpu: wobble(82, 5, 0.5),
      memory: wobble(64, 4, 1.8),
      disk: 84,
      diskIoMbps: wobble(1280, 220, 1.0),
      networkInMbps: wobble(4500, 420, 2.2),
      networkOutMbps: wobble(8200, 680, 1.3),
      latencyMs: 0.8,
      packetLossPct: 0.02,
      cpuTempC: wobble(71, 3, 0.9),
      uptime: "45d 12h",
      exitNode: false,
      subnetRoutes: true,
      activeServices: 12,
      tags: ["storage", "agents", "linux"],
    },
    {
      id: "pi-dns",
      name: "pi-dns",
      role: "DNS",
      status: "online",
      x: 0.54,
      y: 0.27,
      cpu: wobble(16, 5, 2.6),
      memory: wobble(35, 5, 1.1),
      disk: 41,
      diskIoMbps: wobble(12, 5, 0.2),
      networkInMbps: wobble(24, 8, 1.7),
      networkOutMbps: wobble(18, 6, 2.8),
      latencyMs: 2.1,
      packetLossPct: 0,
      cpuTempC: wobble(47, 4, 0.3),
      uptime: "92d 3h",
      exitNode: false,
      subnetRoutes: false,
      activeServices: 3,
      tags: ["dns", "raspberry-pi"],
    },
    {
      id: "media-mac",
      name: "media-mac",
      role: "Media Worker",
      status: "online",
      x: 0.75,
      y: 0.67,
      cpu: wobble(41, 11, 2.4),
      memory: wobble(55, 9, 0.8),
      disk: 57,
      diskIoMbps: wobble(180, 60, 2.2),
      networkInMbps: wobble(210, 70, 0.5),
      networkOutMbps: wobble(320, 100, 1.2),
      latencyMs: 4.4,
      packetLossPct: 0.04,
      cpuTempC: wobble(62, 6, 2.1),
      uptime: "3d 18h",
      exitNode: false,
      subnetRoutes: false,
      activeServices: 7,
      tags: ["media", "macos"],
    },
    {
      id: "work-laptop",
      name: "work-laptop",
      role: "Mobile",
      status: "warning",
      x: 0.49,
      y: 0.78,
      cpu: wobble(52, 18, 1.7),
      memory: wobble(70, 6, 0.9),
      disk: 66,
      diskIoMbps: wobble(140, 50, 1.5),
      networkInMbps: wobble(260, 90, 2.6),
      networkOutMbps: wobble(110, 40, 0.6),
      latencyMs: 7.5,
      packetLossPct: 0.1,
      cpuTempC: wobble(78, 8, 1.2),
      uptime: "18h 22m",
      exitNode: false,
      subnetRoutes: false,
      activeServices: 5,
      tags: ["laptop", "warning"],
    },
    {
      id: "homelab-router",
      name: "homelab-router",
      role: "Router",
      status: "online",
      x: 0.51,
      y: 0.54,
      cpu: wobble(28, 6, 1.9),
      memory: wobble(44, 5, 2.9),
      disk: 35,
      diskIoMbps: wobble(36, 10, 0.9),
      networkInMbps: wobble(920, 260, 1.4),
      networkOutMbps: wobble(870, 230, 2.1),
      latencyMs: 0.6,
      packetLossPct: 0,
      cpuTempC: wobble(55, 4, 1.0),
      uptime: "120d 9h",
      exitNode: true,
      subnetRoutes: true,
      activeServices: 8,
      tags: ["router", "exit-node"],
    },
  ];
}



