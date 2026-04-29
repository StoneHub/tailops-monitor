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
  { entity_id: "binary_sensor.zenwifi_xd5_7890_wan_status", state: "on", attributes: {} },
  { entity_id: "sensor.zenwifi_xd5_7890_wan_status", state: "Connected", attributes: {} },
];

test("mapAsusRouterStatesToStats extracts ASUSWRT router metrics from HA states", () => {
  const stats = mapAsusRouterStatesToStats(states, "2026-04-29T15:00:00.000Z");

  assert.equal(stats.cpu, 31);
  assert.equal(stats.memory, 58);
  assert.equal(stats.cpuTempC, 62.5);
  assert.equal(stats.cpuCores[3].usage, 43);
  assert.equal(stats.memoryFree, 148);
  assert.equal(stats.wan.connected, true);
});

test("routerHostFromHomeAssistant creates a dashboard host for the router", () => {
  const host = routerHostFromHomeAssistant(mapAsusRouterStatesToStats(states));

  assert.equal(host.id, "asus-zenwifi-xd5");
  assert.equal(host.role, "ASUS Router");
  assert.equal(host.status, "online");
  assert.equal(host.cpuTempC, 62.5);
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
      return {
        ok: true,
        json: async () => state,
      };
    },
  });

  assert.equal(stats.available, true);
  assert.equal(stats.cpu, 31);
  assert.equal(requested.length, states.length);
  assert.equal(requested[0].authorization, "Bearer test-token");
});
