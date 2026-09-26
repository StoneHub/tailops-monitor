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
