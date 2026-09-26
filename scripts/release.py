#!/usr/bin/env python3
"""Cut a TailOps release from main: bump the version, test, build and sign, tag, and publish a GitHub pre-release.

Releases are signed with the owner's Apple Development identity (team N6GPP46885) and are not notarized,
so they are published as pre-releases and install only where that certificate is trusted. The in-app
"Check for Updates" button looks for the asset named TailOps-<version>.zip.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile

OWNER_TEAM = 'N6GPP46885'
REPOSITORY = 'StoneHub/tailops-monitor'
INSTALL_PATH = Path('/Applications/TailOps.app')

root = Path(__file__).resolve().parents[1]
os.chdir(root)
project_dir = root / 'platforms/macos/TailOpsMac'
app_plist = project_dir / 'Xcode/TailOpsMacApp/Info.plist'
widget_plist = project_dir / 'Xcode/TailOpsWidget/Info.plist'
pbxproj = project_dir / 'TailOpsMac.xcodeproj/project.pbxproj'
work = root / 'build/release'

parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument('bump', nargs='?', help='patch, minor, major, or an explicit X.Y.Z')
parser.add_argument('--notes', help='Release notes; written to docs/releases/<version>.md and used for the tag and release')
parser.add_argument('--dry-run', action='store_true', help='Bump, test, build, and zip, then restore the tree without committing or publishing')
parser.add_argument('--install', action='store_true', help='After publishing, download the release from GitHub and install it')
parser.add_argument('--install-only', metavar='TAG', help='Download an existing release from GitHub and install it, e.g. v1.1.0')
options = parser.parse_args()


def run(args, quiet=False, cwd=None):
    # Quiet commands show their output only when they fail.
    result = subprocess.run(args, text=True, capture_output=quiet, cwd=cwd)
    if result.returncode != 0:
        if quiet:
            print(result.stdout[-4000:], result.stderr[-4000:], sep='\n', file=sys.stderr)
        raise SystemExit(f'{" ".join(str(a) for a in args[:3])} failed with exit {result.returncode}.')
    return result


def out(args):
    return subprocess.check_output(args, text=True).strip()


def step(message):
    print(f'-> {message}', flush=True)


def signing_team(bundle):
    result = subprocess.run(['codesign', '-dv', str(bundle)], capture_output=True, text=True)
    for line in result.stderr.splitlines():
        if line.startswith('TeamIdentifier='):
            return line.split('=', 1)[1]
    raise SystemExit(f'{bundle} has no signing team.')


def signing_identity():
    """An Apple Development identity whose certificate belongs to the owner team."""
    requested = os.environ.get('TAILOPS_SIGN_IDENTITY')
    identities = re.findall(r'"([^"]+)"', out(['security', 'find-identity', '-v', '-p', 'codesigning']))
    for identity in ([requested] if requested else identities):
        if identity not in identities or not identity.startswith(('Apple Development:', 'Developer ID Application:')):
            continue
        certificate = subprocess.check_output(['security', 'find-certificate', '-c', identity, '-p'])
        subject = subprocess.check_output(['openssl', 'x509', '-noout', '-subject', '-nameopt', 'RFC2253'], input=certificate)
        if f'OU={OWNER_TEAM}' in subject.decode():
            return identity
    raise SystemExit(f'No signing identity for team {OWNER_TEAM} is installed; set TAILOPS_SIGN_IDENTITY.')


def install_release(tag):
    """Download a published release asset, check it against its checksum and signature, and install it."""
    version = tag.removeprefix('v')
    asset = f'TailOps-{version}.zip'
    with tempfile.TemporaryDirectory(prefix='tailops-install-') as scratch:
        scratch = Path(scratch)
        step(f'Downloading {asset} from the {tag} release')
        run(['gh', 'release', 'download', tag, '--repo', REPOSITORY, '--pattern', asset, '--pattern', f'{asset}.sha256',
             '--dir', str(scratch)], quiet=True)
        expected = (scratch / f'{asset}.sha256').read_text().split()[0]
        actual = hashlib.sha256((scratch / asset).read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f'{asset} checksum {actual} does not match the published {expected}.')
        run(['ditto', '-x', '-k', str(scratch / asset), str(scratch)])
        app = scratch / 'TailOps.app'
        run(['codesign', '--verify', '--deep', '--strict', str(app)], quiet=True)
        if signing_team(app) != OWNER_TEAM:
            raise SystemExit(f'{asset} is not signed by team {OWNER_TEAM}.')
        if subprocess.run(['xattr', '-p', 'com.apple.quarantine', str(app)], capture_output=True).returncode == 0:
            raise SystemExit(f'{asset} is quarantined; open it from Finder so Gatekeeper can assess it.')
        built = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
        if built != version:
            raise SystemExit(f'{asset} contains version {built}, expected {version}.')
        step(f'Verified {asset}: checksum, signature, team {OWNER_TEAM}, version {version}')

        # The host app is a login item without a Dock icon; quit it so the bundle can be replaced.
        subprocess.run(['osascript', '-e', 'quit app id "dev.tailops.monitor"'], capture_output=True)
        subprocess.run(['pkill', '-x', 'TailOps'], capture_output=True)
        previous = scratch / 'TailOps-previous.app'
        if INSTALL_PATH.exists():
            run(['mv', str(INSTALL_PATH), str(previous)])
        try:
            run(['ditto', str(app), str(INSTALL_PATH)])
            run(['codesign', '--verify', '--deep', '--strict', str(INSTALL_PATH)], quiet=True)
        except SystemExit:
            if previous.exists():
                subprocess.run(['rm', '-rf', str(INSTALL_PATH)])
                run(['mv', str(previous), str(INSTALL_PATH)])
            raise
        run(['open', str(INSTALL_PATH)])
        step(f'Installed TailOps {version} at {INSTALL_PATH} and launched it')


if options.install_only:
    install_release(options.install_only)
    sys.exit(0)

# a. Preconditions: releases come only from a clean, pushed main with the owner's signing identity.
if not options.bump or not options.notes:
    raise SystemExit('Pass a bump (patch, minor, major, or X.Y.Z) and --notes "text".')
if out(['git', 'branch', '--show-current']) != 'main':
    raise SystemExit('Switch to main; releases are cut from main only.')
if out(['git', 'status', '--porcelain']):
    raise SystemExit('The working tree has changes; commit or stash them first.')
run(['git', 'fetch', 'origin', 'main', '--tags'], quiet=True)
if out(['git', 'rev-parse', 'HEAD']) != out(['git', 'rev-parse', 'origin/main']):
    raise SystemExit('HEAD differs from origin/main; pull or push first.')
if subprocess.run(['gh', 'auth', 'status'], capture_output=True).returncode != 0:
    raise SystemExit('gh is not logged in; run gh auth login.')
identity = signing_identity()
step(f'Preconditions passed on main at {out(["git", "rev-parse", "--short", "HEAD"])}; signing as {identity}')

# b. Version bump. The widget must carry the same version as its app; the build number only increases.
current = plistlib.loads(app_plist.read_bytes())['CFBundleShortVersionString']
parts = [int(n) for n in (current.split('.') + ['0', '0'])[:3]]
if options.bump == 'patch':
    parts[2] += 1
elif options.bump == 'minor':
    parts = [parts[0], parts[1] + 1, 0]
elif options.bump == 'major':
    parts = [parts[0] + 1, 0, 0]
elif re.fullmatch(r'\d+\.\d+\.\d+', options.bump):
    parts = [int(n) for n in options.bump.split('.')]
else:
    raise SystemExit('bump must be patch, minor, major, or X.Y.Z')
version = '.'.join(map(str, parts))
if tuple(parts) <= tuple(int(n) for n in (current.split('.') + ['0', '0'])[:3]):
    raise SystemExit(f'{version} is not newer than the current {current}.')
tag = f'v{version}'
if tag in out(['git', 'tag', '--list']).split():
    raise SystemExit(f'Tag {tag} already exists.')
build_numbers = {int(n) for n in re.findall(r'CURRENT_PROJECT_VERSION = (\d+);', pbxproj.read_text())}
build_number = max(build_numbers) + 1
notes_file = root / f'docs/releases/{version}.md'
if notes_file.exists():
    raise SystemExit(f'{notes_file.relative_to(root)} already exists.')

edits = {}


def rewrite(path, pattern, replacement):
    text = path.read_text()
    new, count = re.subn(pattern, replacement, text)
    if count == 0:
        raise SystemExit(f'No match for {pattern!r} in {path.relative_to(root)}.')
    edits.setdefault(path, text)
    path.write_text(new)


for plist in (app_plist, widget_plist):
    rewrite(plist, r'(<key>CFBundleShortVersionString</key>\s*<string>)[^<]+', rf'\g<1>{version}')
rewrite(pbxproj, r'CURRENT_PROJECT_VERSION = \d+;', f'CURRENT_PROJECT_VERSION = {build_number};')
notes_file.parent.mkdir(parents=True, exist_ok=True)
notes_file.write_text(f'# TailOps {version}\n\n{options.notes.strip()}\n')
edits[notes_file] = None
step(f'Version {current} -> {version} (build {build_number}); notes in {notes_file.relative_to(root)}')


def restore():
    for path, text in edits.items():
        if text is None:
            path.unlink(missing_ok=True)
        else:
            path.write_text(text)


try:
    # c. Tests, then a Release build of the exact product that ships.
    step('npm test and swift test')
    run(['npm', 'test'], quiet=True)
    run(['swift', 'test'], quiet=True, cwd=project_dir)
    step('xcodebuild Release')
    derived = work / 'DerivedData'
    run(['xcodebuild', '-project', str(pbxproj.parent), '-scheme', 'TailOpsMac', '-configuration', 'Release',
         '-destination', 'platform=macOS', '-derivedDataPath', str(derived),
         'CODE_SIGN_STYLE=Manual', f'CODE_SIGN_IDENTITY={identity}', f'DEVELOPMENT_TEAM={OWNER_TEAM}',
         # A development certificate otherwise adds get-task-allow, which a shipped build must not carry.
         'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO', 'build'], quiet=True)
    app = derived / 'Build/Products/Release/TailOps.app'
    run(['codesign', '--verify', '--deep', '--strict', str(app)], quiet=True)
    for bundle in (app, app / 'Contents/PlugIns/TailOpsWidget.appex'):
        if signing_team(bundle) != OWNER_TEAM:
            raise SystemExit(f'{bundle.name} is not signed by team {OWNER_TEAM}.')
        entitlements = subprocess.check_output(['codesign', '-d', '--entitlements', ':-', str(bundle)], stderr=subprocess.DEVNULL)
        if entitlements and plistlib.loads(entitlements).get('com.apple.security.get-task-allow'):
            raise SystemExit(f'{bundle.name} allows debugger attachment in a Release build.')
        built = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
        if built != version:
            raise SystemExit(f'{bundle.name} reports version {built}, expected {version}.')
    step(f'Built and verified {app.relative_to(root)}')

    # d. Package.
    zip_path = work / f'TailOps-{version}.zip'
    zip_path.unlink(missing_ok=True)
    run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(zip_path)])
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    checksum_path = work / f'TailOps-{version}.zip.sha256'
    checksum_path.write_text(f'{digest}  {zip_path.name}\n')
    step(f'Zipped {zip_path.relative_to(root)} ({zip_path.stat().st_size} bytes, sha256 {digest})')

    changed = [str(p.relative_to(root)) for p in edits]
    if options.dry_run:
        step('Dry run: would commit ' + ', '.join(changed))
        step(f'Dry run: would tag {tag}, push main --follow-tags, and publish a pre-release with {zip_path.name}')
        restore()
        step('Dry run: tree restored')
        sys.exit(0)
except BaseException:
    restore()
    raise

# e. One commit and an annotated tag carrying the notes.
run(['git', 'add', '--'] + changed)
# Local release: the gates above already ran here, so skip the GitHub runners (see AGENTS.md).
run(['git', 'commit', '-q', '-m', f'Release {version} [skip ci]'])
run(['git', 'tag', '-a', tag, '-F', str(notes_file)])
step(f'Committed "Release {version}" and tagged {tag}')

# f. Publish. The asset name must stay TailOps-<version>.zip; the in-app updater looks for exactly that.
run(['git', 'push', 'origin', 'main', '--follow-tags'])
step('Pushed main and tag')
run(['gh', 'release', 'create', tag, str(zip_path), str(checksum_path), '--repo', REPOSITORY,
     '--title', f'TailOps {version}', '--notes-file', str(notes_file), '--prerelease'])
step(f'Release {tag} published: ' + out(['gh', 'release', 'view', tag, '--repo', REPOSITORY, '--json', 'url', '--jq', '.url']))

if options.install:
    install_release(tag)
