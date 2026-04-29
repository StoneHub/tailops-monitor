const DEFAULT_HA_URL = "http://100.104.71.37:8123";

export const ASUS_ROUTER_ENTITIES = {
  cpu: "sensor.192_168_50_1_cpu_usage",
  cpuCores: [
    "sensor.192_168_50_1_cpu_core_1_usage",
    "sensor.192_168_50_1_cpu_core_2_usage",
    "sensor.192_168_50_1_cpu_core_3_usage",
    "sensor.192_168_50_1_cpu_core_4_usage",
  ],
  memory: "sensor.192_168_50_1_memory_usage",
  memoryFree: "sensor.192_168_50_1_memory_free",
  memoryUsed: "sensor.192_168_50_1_memory_used",
  cpuTemp: "sensor.192_168_50_1_cpu_temperature",
  devicesConnected: "sensor.192_168_50_1_devices_connected",
  lastBoot: "sensor.192_168_50_1_last_boot",
  wanBinary: "binary_sensor.zenwifi_xd5_7890_wan_status",
  wanStatus: "sensor.zenwifi_xd5_7890_wan_status",
  downloadSpeed: "sensor.zenwifi_xd5_7890_download_speed",
  uploadSpeed: "sensor.zenwifi_xd5_7890_upload_speed",
  externalIp: "sensor.zenwifi_xd5_7890_external_ip",
};

const ENTITY_IDS = [
  ASUS_ROUTER_ENTITIES.cpu,
  ...ASUS_ROUTER_ENTITIES.cpuCores,
  ASUS_ROUTER_ENTITIES.memory,
  ASUS_ROUTER_ENTITIES.memoryFree,
  ASUS_ROUTER_ENTITIES.memoryUsed,
  ASUS_ROUTER_ENTITIES.cpuTemp,
  ASUS_ROUTER_ENTITIES.devicesConnected,
  ASUS_ROUTER_ENTITIES.lastBoot,
  ASUS_ROUTER_ENTITIES.wanBinary,
  ASUS_ROUTER_ENTITIES.wanStatus,
  ASUS_ROUTER_ENTITIES.downloadSpeed,
  ASUS_ROUTER_ENTITIES.uploadSpeed,
  ASUS_ROUTER_ENTITIES.externalIp,
];

function parseNumericState(entity) {
  const value = Number.parseFloat(entity?.state);
  return Number.isFinite(value) ? value : null;
}

function normalizeUnit(entity) {
  return entity?.attributes?.unit_of_measurement ?? "";
}

function kibPerSecondToMbps(value) {
  return typeof value === "number" ? (value * 1024 * 8) / 1_000_000 : 0;
}

function entityById(states) {
  return new Map(states.filter(Boolean).map((state) => [state.entity_id, state]));
}

export function mapAsusRouterStatesToStats(states, generatedAt = new Date().toISOString()) {
  const byId = entityById(states);
  const cpu = parseNumericState(byId.get(ASUS_ROUTER_ENTITIES.cpu));
  const memory = parseNumericState(byId.get(ASUS_ROUTER_ENTITIES.memory));
  const tempEntity = byId.get(ASUS_ROUTER_ENTITIES.cpuTemp);
  const cpuTempC = parseNumericState(tempEntity);
  const devicesConnected = parseNumericState(byId.get(ASUS_ROUTER_ENTITIES.devicesConnected));
  const lastBoot = byId.get(ASUS_ROUTER_ENTITIES.lastBoot)?.state ?? null;
  const wanBinary = byId.get(ASUS_ROUTER_ENTITIES.wanBinary)?.state ?? null;
  const wanStatus = byId.get(ASUS_ROUTER_ENTITIES.wanStatus)?.state ?? null;
  const downloadKibPerSec = parseNumericState(byId.get(ASUS_ROUTER_ENTITIES.downloadSpeed));
  const uploadKibPerSec = parseNumericState(byId.get(ASUS_ROUTER_ENTITIES.uploadSpeed));
  const externalIp = byId.get(ASUS_ROUTER_ENTITIES.externalIp)?.state ?? null;

  return {
    id: "asus-zenwifi-xd5",
    name: "ZenWiFi XD5",
    source: "home-assistant",
    generatedAt,
    homeAssistantUrl: null,
    cpu,
    memory,
    cpuTempC,
    cpuTempUnit: normalizeUnit(tempEntity) || "C",
    devicesConnected,
    lastBoot,
    externalIp,
    networkInMbps: kibPerSecondToMbps(downloadKibPerSec),
    networkOutMbps: kibPerSecondToMbps(uploadKibPerSec),
    rawSpeed: {
      downloadKibPerSec,
      uploadKibPerSec,
    },
    cpuCores: ASUS_ROUTER_ENTITIES.cpuCores.map((entityId, index) => ({
      core: index + 1,
      entityId,
      usage: parseNumericState(byId.get(entityId)),
    })),
    memoryFree: parseNumericState(byId.get(ASUS_ROUTER_ENTITIES.memoryFree)),
    memoryUsed: parseNumericState(byId.get(ASUS_ROUTER_ENTITIES.memoryUsed)),
    wan: {
      connected: wanBinary === "on" || wanStatus === "Connected",
      binaryState: wanBinary,
      status: wanStatus,
    },
    entities: ENTITY_IDS,
    available: true,
  };
}

export function routerHostFromHomeAssistant(stats) {
  return {
    id: stats.id,
    name: stats.name,
    role: "ASUS Router",
    os: "asuswrt",
    status: stats.wan?.connected === false ? "warning" : "online",
    x: 0.5,
    y: 0.53,
    cpu: stats.cpu,
    memory: stats.memory,
    disk: null,
    diskIoMbps: 0,
    networkInMbps: stats.networkInMbps ?? 0,
    networkOutMbps: stats.networkOutMbps ?? 0,
    rxBytes: 0,
    txBytes: 0,
    latencyMs: 0.6,
    packetLossPct: null,
    cpuTempC: stats.cpuTempC,
    uptime: stats.lastBoot ? `booted ${new Date(stats.lastBoot).toLocaleString()}` : stats.wan?.status ?? "unknown",
    exitNode: false,
    subnetRoutes: true,
    activeServices: stats.devicesConnected ?? 2,
    tags: ["router", "asuswrt", "home-assistant"],
    tailscaleIp: null,
    magicDns: null,
    active: true,
    relay: "",
    homeAssistant: stats,
  };
}

export async function fetchHomeAssistantRouterStats(options = {}) {
  const token = options.token ?? process.env.TAILOPS_HA_TOKEN ?? "";
  const baseUrl = (options.url ?? process.env.TAILOPS_HA_URL ?? DEFAULT_HA_URL).replace(/\/$/, "");
  const fetchImpl = options.fetchImpl ?? globalThis.fetch;
  if (!token) {
    return {
      available: false,
      source: "home-assistant",
      homeAssistantUrl: baseUrl,
      error: "TAILOPS_HA_TOKEN is not set",
    };
  }
  if (typeof fetchImpl !== "function") {
    return {
      available: false,
      source: "home-assistant",
      homeAssistantUrl: baseUrl,
      error: "fetch is not available in this Node runtime",
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), options.timeoutMs ?? 5000);
  try {
    const states = [];
    for (const entityId of ENTITY_IDS) {
      const response = await fetchImpl(`${baseUrl}/api/states/${entityId}`, {
        headers: {
          Authorization: `Bearer ${token}`,
          Accept: "application/json",
        },
        signal: controller.signal,
      });
      if (response.status === 404) {
        continue;
      }
      if (!response.ok) {
        throw new Error(`Home Assistant ${entityId} returned ${response.status}`);
      }
      states.push(await response.json());
    }
    const stats = mapAsusRouterStatesToStats(states);
    stats.homeAssistantUrl = baseUrl;
    return stats;
  } catch (error) {
    return {
      available: false,
      source: "home-assistant",
      homeAssistantUrl: baseUrl,
      error: error.name === "AbortError" ? "Home Assistant request timed out" : error.message,
    };
  } finally {
    clearTimeout(timeout);
  }
}
