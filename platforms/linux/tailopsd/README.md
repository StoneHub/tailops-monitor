# tailopsd

`tailopsd` is a read-only Linux CLI for producing one versioned TailOps Fleet observation from the local Tailscale daemon. FCFDEV is the first install target, but the project is for Linux and contains no architecture-specific code.

The project is a collector, not a network daemon. It opens no listener, accepts no remote command, performs no SSH, and does not import the private Fleet registry. A Fleet transport adapter can invoke the CLI and attach its result to the Fleet task envelope without changing the collector.

## Requirements

- Linux
- Node.js 20 or newer
- a working local `tailscale` CLI and daemon

## Run

```bash
node bin/tailopsd.js snapshot --pretty
```

Check whether the host can run the CLI and the optional systemd timer:

```bash
node bin/tailopsd.js doctor --pretty
```

Write a snapshot atomically with mode `600`:

```bash
node bin/tailopsd.js snapshot --output /absolute/path/fleet-observation.json
```

Each snapshot also records the collector node's own read-only health under `host`: OS, kernel, uptime, load, memory, root disk, failed systemd units, and the hottest thermal sensor. `host.warnings` lists what needs attention: a root disk at least 90% full, memory at or below 10% available, any failed unit, or a sensor at 80 °C or hotter. A probe that cannot run is listed in `host.probeErrors` without failing the snapshot. Pass `--no-host` for the tailnet view alone.

`--health-output PATH` also writes a health-only document (`tailops.host-health`) with the collector, node counts, and host health but no peer list or addresses, at mode 644. The systemd unit writes it to `/var/lib/tailopsd/host-health.json`; TailOps on a Mac reads that file over the controller's existing SSH login to show the node's health in its widget.

Mullvad exit nodes carrying `tag:mullvad-exit-node` are excluded by default. Include provider infrastructure only for diagnostics:

```bash
node bin/tailopsd.js snapshot --all-peers --pretty
```

## Validate

```bash
npm test
```

Build the installable package:

```bash
npm run pack:linux
```

The optional systemd adapter uses a restricted `tailopsd` account and a 15-minute oneshot timer. See the [Linux runbook](../../../docs/runbooks/linux-tailopsd.md) before installing it.

Source tests prove the CLI contract, atomic file behavior, runtime-doctor behavior, and provider-node policy. Package, host, install, runtime, schedule, and Fleet-transport proof remain separate.
