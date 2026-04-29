import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";

const root = resolve(new URL("..", import.meta.url).pathname.slice(1));
const mimeTypes = new Map([
  [".html", "text/html; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".png", "image/png"],
  [".svg", "image/svg+xml"],
]);

export function resolveStaticRequest(urlPath) {
  if (urlPath.includes("..")) return { kind: "not-found" };
  const cleanPath = decodeURIComponent(new URL(urlPath, "http://tailops.local").pathname);
  if (cleanPath === "/api/agents") {
    return {
      kind: "agents",
      path: join(root, "data", "agents.sample.json"),
      contentType: "application/json; charset=utf-8",
    };
  }

  const relative = cleanPath === "/" ? "index.html" : cleanPath.slice(1);
  const normalized = normalize(relative);
  if (normalized.startsWith("..") || normalized.includes(":") || normalized.startsWith("\\")) {
    return { kind: "not-found" };
  }

  const filePath = join(root, normalized);
  if (!filePath.startsWith(root)) return { kind: "not-found" };

  return {
    kind: "file",
    path: filePath,
    contentType: mimeTypes.get(extname(filePath)) ?? "application/octet-stream",
  };
}

export function createTailopsServer() {
  return createServer(async (request, response) => {
    const result = resolveStaticRequest(request.url ?? "/");
    if (result.kind === "not-found") {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("Not found");
      return;
    }

    try {
      const content = await readFile(result.path);
      response.writeHead(200, {
        "content-type": result.contentType,
        "cache-control": result.kind === "agents" ? "no-store" : "no-cache",
        "access-control-allow-origin": "*",
      });
      response.end(content);
    } catch {
      response.writeHead(404, { "content-type": "text/plain; charset=utf-8" });
      response.end("Not found");
    }
  });
}

