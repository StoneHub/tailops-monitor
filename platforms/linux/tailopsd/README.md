# tailopsd

`tailopsd` is a read-only Linux CLI for producing one versioned TailOps Fleet observation from the local Tailscale daemon. It is intended for ARM64 FCFDEV first, but it has no native dependencies or architecture-specific code.

This first slice is a collector, not a resident daemon. It opens no listener, accepts no remote command, performs no SSH, and does not import the private Fleet registry. A Fleet transport adapter can invoke the CLI later and attach its result to the Fleet task envelope without changing the collector.

## Requirements

- Linux on ARM64 or x86_64
- Node.js 20 or newer
- a working local `tailscale` CLI and daemon

## Run

```bash
node bin/tailopsd.js snapshot --pretty
```

Mullvad exit nodes carrying `tag:mullvad-exit-node` are excluded by default. Include provider infrastructure only for diagnostics:

```bash
node bin/tailopsd.js snapshot --all-peers --pretty
```

## Validate

```bash
npm test
```

Source tests prove the CLI contract and provider-node policy. They do not prove that FCFDEV has the required runtime, that the CLI is installed there, or that a Fleet transport can invoke it.
