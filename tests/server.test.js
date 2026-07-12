import test from "node:test";
import assert from "node:assert/strict";
import { once } from "node:events";
import { isLoopbackHost, resolveServerConfig } from "../server.js";
import { createTailopsServer, resolveStaticRequest } from "../src/server.js";

async function withServer(options, callback) {
  const server = createTailopsServer(options);
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    const address = server.address();
    await callback(`http://127.0.0.1:${address.port}`);
  } finally {
    const closed = once(server, "close");
    server.close();
    await closed;
  }
}

test("resolveServerConfig defaults to loopback with CORS disabled", () => {
  assert.deepEqual(resolveServerConfig({}), {
    host: "127.0.0.1",
    port: 4173,
    corsOrigin: null,
  });
});

test("resolveServerConfig accepts explicit network and CORS configuration", () => {
  assert.deepEqual(
    resolveServerConfig({
      HOST: "0.0.0.0",
      PORT: "8080",
      TAILOPS_CORS_ORIGIN: "https://console.example.test",
    }),
    {
      host: "0.0.0.0",
      port: 8080,
      corsOrigin: "https://console.example.test",
    },
  );
  assert.equal(isLoopbackHost("127.0.0.1"), true);
  assert.equal(isLoopbackHost("0.0.0.0"), false);
});

test("HTTP responses do not allow cross-origin access by default", async () => {
  await withServer({}, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/.well-known/agent.json`, {
      headers: { origin: "https://console.example.test" },
    });

    assert.equal(response.status, 200);
    assert.equal(response.headers.get("access-control-allow-origin"), null);
  });
});

test("HTTP responses allow only the explicitly configured CORS origin", async () => {
  await withServer({ corsOrigin: "https://console.example.test" }, async (baseUrl) => {
    const allowed = await fetch(`${baseUrl}/.well-known/agent.json`, {
      headers: { origin: "https://console.example.test" },
    });
    const denied = await fetch(`${baseUrl}/.well-known/agent.json`, {
      headers: { origin: "https://other.example.test" },
    });

    assert.equal(allowed.headers.get("access-control-allow-origin"), "https://console.example.test");
    assert.equal(allowed.headers.get("vary"), "Origin");
    assert.equal(denied.headers.get("access-control-allow-origin"), null);
  });
});

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
