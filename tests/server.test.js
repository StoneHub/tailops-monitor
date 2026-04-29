import test from "node:test";
import assert from "node:assert/strict";
import { resolveStaticRequest } from "../src/server.js";

test("resolveStaticRequest maps /api/agents to JSON response metadata", () => {
  const result = resolveStaticRequest("/api/agents");

  assert.equal(result.kind, "agents");
  assert.equal(result.contentType, "application/json; charset=utf-8");
});

test("resolveStaticRequest maps /api/telemetry to live telemetry metadata", () => {
  const result = resolveStaticRequest("/api/telemetry");

  assert.equal(result.kind, "telemetry");
  assert.equal(result.contentType, "application/json; charset=utf-8");
});

test("resolveStaticRequest maps A2A agent discovery endpoints", () => {
  const googleStyle = resolveStaticRequest("/.well-known/agent.json");
  const cardStyle = resolveStaticRequest("/.well-known/agent-card.json");

  assert.equal(googleStyle.kind, "agent-card");
  assert.equal(cardStyle.kind, "agent-card");
  assert.equal(googleStyle.contentType, "application/json; charset=utf-8");
});

test("resolveStaticRequest maps root to index.html", () => {
  const result = resolveStaticRequest("/");

  assert.equal(result.kind, "file");
  assert.equal(result.path.endsWith("index.html"), true);
  assert.equal(result.contentType, "text/html; charset=utf-8");
});

test("resolveStaticRequest rejects traversal attempts", () => {
  const result = resolveStaticRequest("/../secret.txt");

  assert.equal(result.kind, "not-found");
});
