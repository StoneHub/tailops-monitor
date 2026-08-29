import { buildFleetObservation } from "./fleet-observation.js";
import { collectTailscaleStatus } from "./tailscale-command.js";

const HELP = `Usage: tailopsd snapshot [--all-peers] [--pretty]

Commands:
  snapshot     Print one read-only TailOps Fleet observation as JSON.

Options:
  --all-peers  Include provider nodes such as Mullvad exit nodes.
  --pretty     Pretty-print the JSON result.
  -h, --help   Show this help.
`;

function writeLine(write, value) {
  write(value.endsWith("\n") ? value : `${value}\n`);
}

export async function runCLI(
  args,
  {
    collectStatus = collectTailscaleStatus,
    now = () => new Date(),
    writeStdout = (value) => process.stdout.write(value),
    writeStderr = (value) => process.stderr.write(value),
  } = {},
) {
  if (args.includes("--help") || args.includes("-h")) {
    writeStdout(HELP);
    return 0;
  }

  if (args[0] !== "snapshot") {
    writeLine(writeStderr, "tailopsd: expected the snapshot command");
    writeStderr(HELP);
    return 2;
  }

  const allowedOptions = new Set(["--all-peers", "--pretty"]);
  const unknownOption = args.slice(1).find((argument) => !allowedOptions.has(argument));
  if (unknownOption) {
    writeLine(writeStderr, `tailopsd: unknown option ${unknownOption}`);
    return 2;
  }

  try {
    const status = await collectStatus();
    const observation = buildFleetObservation(status, {
      includeProviderNodes: args.includes("--all-peers"),
      observedAt: now().toISOString(),
    });
    const spacing = args.includes("--pretty") ? 2 : 0;
    writeLine(writeStdout, JSON.stringify(observation, null, spacing));
    return 0;
  } catch (error) {
    writeLine(writeStderr, `tailopsd: ${error.message}`);
    return 3;
  }
}
