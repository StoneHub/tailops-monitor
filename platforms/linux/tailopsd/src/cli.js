import { createRequire } from "node:module";

import { writeObservationFile } from "./atomic-snapshot.js";
import { buildFleetObservation } from "./fleet-observation.js";
import { inspectLinuxRuntime } from "./runtime-doctor.js";
import { collectTailscaleStatus } from "./tailscale-command.js";

const require = createRequire(import.meta.url);
const { version } = require("../package.json");

const HELP = `Usage:
  tailopsd snapshot [--all-peers] [--pretty] [--output ABSOLUTE_PATH]
  tailopsd doctor [--pretty]
  tailopsd version

Commands:
  snapshot     Produce one read-only TailOps Fleet observation.
  doctor       Check the Linux CLI and optional systemd-timer requirements.
  version      Print the installed tailopsd version.

Options:
  --all-peers  Include provider nodes such as Mullvad exit nodes.
  --pretty     Pretty-print the JSON result.
  --output     Atomically write the observation to an absolute path.
  -h, --help   Show this help.
`;

function writeLine(write, value) {
  write(value.endsWith("\n") ? value : `${value}\n`);
}

export async function runCLI(
  args,
  {
    collectStatus = collectTailscaleStatus,
    inspectRuntime = inspectLinuxRuntime,
    writeObservation = writeObservationFile,
    now = () => new Date(),
    writeStdout = (value) => process.stdout.write(value),
    writeStderr = (value) => process.stderr.write(value),
  } = {},
) {
  if (args.includes("--help") || args.includes("-h")) {
    writeStdout(HELP);
    return 0;
  }

  if (args[0] === "version" || args[0] === "--version") {
    writeLine(writeStdout, `tailopsd ${version}`);
    return 0;
  }

  if (args[0] === "doctor") {
    const unknownDoctorOption = args.slice(1).find((argument) => argument !== "--pretty");
    if (unknownDoctorOption) {
      writeLine(writeStderr, `tailopsd: unknown option ${unknownDoctorOption}`);
      return 2;
    }

    const report = await inspectRuntime({
      collectStatus,
      observedAt: now().toISOString(),
    });
    writeLine(writeStdout, JSON.stringify(report, null, args.includes("--pretty") ? 2 : 0));
    return report.status === "ready" ? 0 : 4;
  }

  if (args[0] !== "snapshot") {
    writeLine(writeStderr, "tailopsd: expected snapshot, doctor, or version");
    writeStderr(HELP);
    return 2;
  }

  let outputPath = null;
  const snapshotFlags = [];
  for (let index = 1; index < args.length; index += 1) {
    const argument = args[index];
    if (argument === "--output") {
      outputPath = args[index + 1] ?? null;
      if (!outputPath || outputPath.startsWith("--")) {
        writeLine(writeStderr, "tailopsd: --output requires an absolute path");
        return 2;
      }
      index += 1;
    } else if (argument === "--all-peers" || argument === "--pretty") {
      snapshotFlags.push(argument);
    } else {
      writeLine(writeStderr, `tailopsd: unknown option ${argument}`);
      return 2;
    }
  }

  try {
    const status = await collectStatus();
    const observation = buildFleetObservation(status, {
      includeProviderNodes: snapshotFlags.includes("--all-peers"),
      observedAt: now().toISOString(),
    });

    if (outputPath) {
      await writeObservation(outputPath, observation);
      writeLine(writeStdout, JSON.stringify({
        schemaVersion: 1,
        kind: "tailops.snapshot-write",
        status: "written",
        path: outputPath,
        observedAt: observation.observedAt,
        nodeCount: observation.summary.nodeCount,
      }));
    } else {
      const spacing = snapshotFlags.includes("--pretty") ? 2 : 0;
      writeLine(writeStdout, JSON.stringify(observation, null, spacing));
    }
    return 0;
  } catch (error) {
    writeLine(writeStderr, `tailopsd: ${error.message}`);
    return 3;
  }
}
