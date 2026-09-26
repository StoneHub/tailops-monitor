# Linux tailopsd

This runbook installs the architecture-neutral `tailopsd` Node package on a Linux host. FCFDEV is the first target. The CLI remains usable without systemd; the supplied systemd files are an optional packaging adapter.

## Proof gates

Keep these facts separate:

- Source: tests pass for the committed package.
- Package: the `.tgz` contains the expected CLI, source, and systemd files.
- Host: `tailopsd doctor` passes under the intended service account.
- Install: `/opt/tailopsd/current` resolves to the intended version.
- Runtime: the oneshot unit exits successfully and writes a current owner-only snapshot.
- Scheduling: the timer is enabled and has a next-run timestamp.
- Fleet integration: a separate authorized transport attaches the observation as evidence. The snapshot file alone does not prove this.

## Build

From the repository root:

```bash
npm run pack:linux
```

The package is written under `platforms/linux/tailopsd/dist/`. Building a package does not install or run it.

## Host preflight

Before installing, verify the target directly:

```bash
uname -sr
cat /etc/os-release
node --version
systemctl --version
tailscale version
tailscale status --json >/dev/null
```

Stop if Linux, Node 20 or newer, or local Tailscale status access is missing. A host without systemd may use the CLI but cannot use the supplied timer.

## Staged install

Copy the package to the host, then replace `0.1.0` below with the package version:

```bash
sudo install -d -m 0755 /opt/tailopsd/releases/0.1.0
sudo tar -xzf tailops-tailopsd-0.1.0.tgz --strip-components=1 -C /opt/tailopsd/releases/0.1.0
sudo systemd-sysusers /opt/tailopsd/releases/0.1.0/packaging/systemd/tailopsd.sysusers
sudo systemd-tmpfiles --create /opt/tailopsd/releases/0.1.0/packaging/systemd/tailopsd.tmpfiles
sudo -u tailopsd /opt/tailopsd/releases/0.1.0/bin/tailopsd.js doctor --pretty
```

The doctor must report both the CLI and systemd-timer profiles as `ready`. If it blocks, stop before installing units or enabling the timer.

After the doctor passes:

```bash
sudo ln -sfn /opt/tailopsd/releases/0.1.0 /opt/tailopsd/current
sudo install -m 0644 /opt/tailopsd/current/packaging/systemd/tailopsd.service /etc/systemd/system/tailopsd.service
sudo install -m 0644 /opt/tailopsd/current/packaging/systemd/tailopsd.timer /etc/systemd/system/tailopsd.timer
sudo systemctl daemon-reload
sudo systemctl start tailopsd.service
sudo systemctl enable --now tailopsd.timer
```

The oneshot unit has no retry policy. The timer runs every 15 minutes with a small randomized delay. The unit caps CPU at 5 percent, memory at 128 MiB, and tasks at 32 so a failure cannot consume the host's wider capacity.

## Runtime proof

```bash
sudo systemctl status tailopsd.service --no-pager
systemctl list-timers tailopsd.timer --no-pager
sudo stat -c '%a %U %G %n' /var/lib/tailopsd/fleet-observation.json
sudo jq '{kind, schemaVersion, policy, observedAt, summary}' /var/lib/tailopsd/fleet-observation.json
```

Expected snapshot mode is `600`, owned by `tailopsd`. Do not print the full node list into public logs or pull requests.

## Disable without deleting state

```bash
sudo systemctl disable --now tailopsd.timer
```

Leave `/var/lib/tailopsd` and installed releases in place until their evidence and rollback value have been reviewed.
