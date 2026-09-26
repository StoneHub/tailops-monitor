import assert from "node:assert/strict";
import { mkdtemp, readFile, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { writeObservationFile } from "../src/atomic-snapshot.js";

test("observation files replace atomically with owner-only permissions", async (context) => {
  const directory = await mkdtemp(join(tmpdir(), "tailopsd-test-"));
  context.after(async () => {
    const { rm } = await import("node:fs/promises");
    await rm(directory, { recursive: true, force: true });
  });
  const outputPath = join(directory, "fleet-observation.json");
  const observation = { schemaVersion: 1, kind: "tailops.fleet-observation" };

  await writeObservationFile(outputPath, observation, { createID: () => "fixed" });

  assert.deepEqual(JSON.parse(await readFile(outputPath, "utf8")), observation);
  assert.equal((await stat(outputPath)).mode & 0o777, 0o600);
});

test("observation files require an absolute output path", async () => {
  await assert.rejects(
    writeObservationFile("snapshot.json", {}),
    /must be absolute/,
  );
});
