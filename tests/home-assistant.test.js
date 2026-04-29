import test from "node:test";
import assert from "node:assert/strict";
import {
  mapAsusRouterStatesToStats,
  routerHostFromHomeAssistant,
  fetchHomeAssistantRouterStats,
} from "../src/home-assistant.js";

const states = [
  { entity_id: "sensor.192_168_50_1_cpu_usage", state: "31", attributes: { unit_of_measurement: "%" } },
  { entity_id: "sensor.192_168_50_1_cpu_core_1_usage", state: "22", attributes: { unit_of_measurement: "%" } },
  { entity_id: "sensor.192_168_50_1_cpu_core_2_usage", state: "24", attributes: { unit_of_measurement: "%" } },
  { entity_id: "sensor.192_168_50_1_cpu_core_3_usage", state: "35", attributes: { unit_of_measurement: "%" } },
  { entity_id: "sensor.192_168_50_1_cpu_core_4_usage", state: "43", attributes: { unit_of_measurement: "%" } },
  { entity_id: "sensor.192_168_50_1_memory_usage", state: "58", attributes: { unit_of_measurement: "%" } },
  { entity_id: "sensor.192_168_50_1_memory_free", state: "148", attributes: { unit_of_measurement: "MB" } },
  { entity_id: "sensor.192_168_50_1_memory_used", state: "206", attributes: { unit_of_measurement: "MB" } },
  { entity_id: "sensor.192_168_50_1_cpu_temperature", state: "62.5", attributes: { unit_of_measurement: "C" } },
  { entity_id: "sensor.192_168_50_1_devices_connected", state: "59", attributes: { unit_of_measurement: "Devices" } },
  { entity_id: "sensor.192_168_50_1_last_boot", state: "2026-04-23T03:29:00-04:00", attributes: {} },
  { entity_id: "binary_sensor.zenwifi_xd5_7890_wan_status", state: "on", attributes: {} },
  { entity_id: "sensor.zenwifi_xd5_7890_wan_status", state: "Connected", attributes: {} },
  { entity_id: "sensor.zenwifi_xd5_7890_download_speed", state: "24.8938753123956", attributes: { unit_of_measurement: "KiB/s" } },
  { entity_id: "sensor.zenwifi_xd5_7890_upload_speed", state: "114.968949743947", attributes: { unit_of_measurement: "KiB/s" } },
  { entity_id: "sensor.zenwifi_xd5_7890_external_ip", state: "192.168.1.101", attributes: {} },
];

test("mapAsusRouterStatesToStats extracts ASUSWRT router metrics from HA states", () => {
  const stats = mapAsusRouterStatesToStats(states, "2026-04-29T15:00:00.000Z");

  assert.equal(stats.cpu, 31);
  assert.equal(stats.memory, 58);
  assert.equal(stats.cpuTempC, 62.5);
  assert.equal(stats.cpuCores[3].usage, 43);
  assert.equal(stats.memoryFree, 148);
  assert.equal(stats.wan.connected, true);
  assert.equal(stats.devicesConnected, 59);
  assert.equal(stats.externalIp, "192.168.1.101");
  assert.ok(stats.networkInMbps > 0);
  assert.ok(stats.networkOutMbps > stats.networkInMbps);
});

test("routerHostFromHomeAssistant creates a dashboard host for the router", () => {
  const host = routerHostFromHomeAssistant(mapAsusRouterStatesToStats(states));

  assert.equal(host.id, "asus-zenwifi-xd5");
  assert.equal(host.role, "ASUS Router");
  assert.equal(host.status, "online");
  assert.equal(host.cpuTempC, 62.5);
  assert.equal(host.activeServices, 59);
  assert.ok(host.networkOutMbps > host.networkInMbps);
  assert.equal(host.tags.includes("home-assistant"), true);
});

test("fetchHomeAssistantRouterStats reports missing token without network access", async () => {
  const stats = await fetchHomeAssistantRouterStats({
    token: "",
    url: "http://homeassistant.local:8123",
    fetchImpl: () => {
      throw new Error("should not fetch without a token");
    },
  });

  assert.equal(stats.available, false);
  assert.equal(stats.homeAssistantUrl, "http://homeassistant.local:8123");
  assert.match(stats.error, /TAILOPS_HA_TOKEN/);
});

test("fetchHomeAssistantRouterStats reads each configured entity with bearer auth", async () => {
  const requested = [];
  const stats = await fetchHomeAssistantRouterStats({
    token: "test-token",
    url: "http://homeassistant.local:8123/",
    fetchImpl: async (url, options) => {
      requested.push({ url, authorization: options.headers.Authorization });
      const entityId = decodeURIComponent(url.split("/api/states/")[1]);
      const state = states.find((entry) => entry.entity_id === entityId);
      if (!state) return { ok: false, status: 404 };
      return {
        ok: true,
        json: async () => state,
      };
    },
  });

  assert.equal(stats.available, true);
  assert.equal(stats.cpu, 31);
  assert.ok(requested.length >= states.length);
  assert.equal(requested[0].authorization, "Bearer test-token");
});

test("fetchHomeAssistantRouterStats tolerates missing optional ASUS entities", async () => {
  const availableStates = states.filter((entry) =>
    [
      "binary_sensor.zenwifi_xd5_7890_wan_status",
      "sensor.192_168_50_1_devices_connected",
      "sensor.zenwifi_xd5_7890_download_speed",
      "sensor.zenwifi_xd5_7890_upload_speed",
    ].includes(entry.entity_id),
  );

  const stats = await fetchHomeAssistantRouterStats({
    token: "test-token",
    url: "http://homeassistant.local:8123/",
    fetchImpl: async (url) => {
      const entityId = decodeURIComponent(url.split("/api/states/")[1]);
      const state = availableStates.find((entry) => entry.entity_id === entityId);
      if (!state) return { ok: false, status: 404 };
      return {
        ok: true,
        json: async () => state,
      };
    },
  });

  assert.equal(stats.available, true);
  assert.equal(stats.cpu, null);
  assert.equal(stats.devicesConnected, 59);
  assert.equal(stats.wan.connected, true);
  assert.ok(stats.networkOutMbps > 0);
});
