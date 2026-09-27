import { randomUUID } from "node:crypto";
import { chmod, rename, unlink, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join } from "node:path";

export async function writeObservationFile(
  filePath,
  observation,
  {
    createID = randomUUID,
    write = writeFile,
    setMode = chmod,
    move = rename,
    remove = unlink,
    mode = 0o600,
  } = {},
) {
  if (typeof filePath !== "string" || !isAbsolute(filePath)) {
    throw new TypeError("snapshot output path must be absolute");
  }

  const temporaryPath = join(dirname(filePath), `.${basename(filePath)}.${createID()}.tmp`);
  const data = `${JSON.stringify(observation)}\n`;

  try {
    await write(temporaryPath, data, { encoding: "utf8", mode: 0o600, flag: "wx" });
    // Set the final mode explicitly: the service's umask would otherwise strip read bits.
    await setMode(temporaryPath, mode);
    await move(temporaryPath, filePath);
  } catch (error) {
    await remove(temporaryPath).catch(() => {});
    throw error;
  }
}
