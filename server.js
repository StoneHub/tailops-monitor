import { createTailopsServer } from "./src/server.js";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

export function resolveServerConfig(environment = process.env) {
  return {
    host: environment.HOST?.trim() || "127.0.0.1",
    port: Number(environment.PORT || 4173),
    corsOrigin: environment.TAILOPS_CORS_ORIGIN?.trim() || null,
  };
}

export function isLoopbackHost(host) {
  return host === "127.0.0.1" || host === "::1" || host === "localhost";
}

function startServer() {
  const { host, port, corsOrigin } = resolveServerConfig();
  const server = createTailopsServer({ corsOrigin });

  if (!isLoopbackHost(host)) {
    console.warn(
      `WARNING: TailOps is listening on non-loopback host ${host} without authentication. ` +
        "Only use this on a trusted LAN or tailnet.",
    );
  }

  server.listen(port, host, () => {
    console.log(`TailOps Monitor available on http://${host}:${port}`);
    console.log("Agent phonebook available at /api/agents");
    if (corsOrigin) console.log(`Cross-origin browser access allowed for ${corsOrigin}`);
  });
}

const invokedPath = process.argv[1] ? resolve(process.argv[1]) : null;
if (invokedPath === fileURLToPath(import.meta.url)) startServer();
