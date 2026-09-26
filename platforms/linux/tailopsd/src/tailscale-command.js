import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export async function collectTailscaleStatus({ run = execFileAsync } = {}) {
  let stdout;

  try {
    ({ stdout } = await run("tailscale", ["status", "--json"], {
      encoding: "utf8",
      timeout: 10_000,
      maxBuffer: 4 * 1024 * 1024,
      windowsHide: true,
    }));
  } catch (cause) {
    throw new Error("tailscale status --json failed", { cause });
  }

  try {
    return JSON.parse(stdout);
  } catch (cause) {
    throw new Error("tailscale status --json returned invalid JSON", { cause });
  }
}
