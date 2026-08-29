# Linux Fleet observation CLI

TailOps will add a CLI-only Linux collector under `platforms/linux/tailopsd`, with ARM64 FCFDEV as the first intended node. The first slice runs `tailscale status --json` through a bounded, shell-free process adapter and emits a versioned `tailops.fleet-observation` JSON document. It excludes Mullvad provider nodes by default and performs no mutation.

The collector is transport-neutral. It does not open a service listener, accept arbitrary commands, perform SSH, import Fleet registry files, or claim that its output is durable Fleet identity. A separate Fleet worker or Threadspace transport adapter may invoke it and attach the observation as evidence under Fleet's task-envelope contract.

This ADR records source architecture only. FCFDEV CPU architecture, Linux distribution, Node runtime, Tailscale permissions, installation, service packaging, and live output remain separate proof gates.
