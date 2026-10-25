#!/usr/bin/env python3
"""Build native macOS/Linux installers and portable bundles on the host OS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'packages/showrunner-flutter'

def run(*args, cwd=ROOT):
    subprocess.run([str(arg) for arg in args], cwd=cwd, check=True)

def launcher(path, content):
    path.write_text(content, encoding='utf-8')
    path.chmod(0o755)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', required=True)
    parser.add_argument('--build', required=True, type=int)
    parser.add_argument('--require-client', action='store_true')
    args = parser.parse_args()
    if not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?', args.version) or not 1 <= args.build <= 65535:
        parser.error('Invalid version or build number')
    system = platform.system()
    if system not in ('Darwin', 'Linux'):
        parser.error('Run this tool on macOS or Linux')
    arch = {'arm64': 'arm64', 'aarch64': 'arm64', 'x86_64': 'x64'}.get(platform.machine())
    if arch is None or (system == 'Linux' and arch != 'x64'):
        parser.error('Unsupported package architecture')
    client = os.environ.get('SHOWRUNNER_YOUTUBE_CLIENT_ID', '').strip()
    if args.require_client and not client:
        parser.error('A bundled YouTube OAuth client ID is required for a release build')
    target = 'macos' if system == 'Darwin' else 'linux'
    stage = ROOT / '.tmp/desktop-packages' / (target + '-' + arch)
    stage.mkdir(parents=True, exist_ok=True)
    # Build definitions remain outside argv/logs, including the optional client secret.
    defines = {'SHOWRUNNER_VERSION': args.version}
    for key in ('SHOWRUNNER_YOUTUBE_CLIENT_ID', 'SHOWRUNNER_YOUTUBE_CLIENT_SECRET'):
        if os.environ.get(key):
            defines[key] = os.environ[key]
    definitions = stage / 'build-defines.json'
    definitions.write_text(json.dumps(defines), encoding='utf-8')
    definitions.chmod(0o600)
    native = args.version.split('-')[0]
    command = ['flutter', 'build', target, '--release', '--no-pub', '--build-name=' + native,
               '--build-number=' + str(args.build), '--dart-define-from-file=' + str(definitions)]
    if target == 'macos':
        # Do not require Apple provisioning identities on public build runners.
        command.append('--config-only')
        run(*command, cwd=APP)
        run('xcodebuild', '-workspace', 'Runner.xcworkspace', '-scheme', 'Runner', '-configuration', 'Release',
            '-derivedDataPath', '../build/macos', 'ARCHS=' + ('arm64' if arch == 'arm64' else 'x86_64'),
            'ONLY_ACTIVE_ARCH=YES', 'CODE_SIGNING_ALLOWED=NO', cwd=APP / 'macos')
        bundle = APP / 'build/macos/Build/Products/Release/ShowRunner.app'
    else:
        run(*command, cwd=APP)
        bundle = APP / 'build/linux/x64/release/bundle'
    if not bundle.is_dir():
        raise RuntimeError('Native build did not produce its expected application bundle')
    destination = stage / ('ShowRunner.app' if target == 'macos' else 'ShowRunner')
    if destination.exists():
        raise RuntimeError('Package staging directory is not clean; use a fresh build workspace')
    shutil.copytree(bundle, destination, symlinks=True)
    binary_directory = destination / 'Contents/MacOS' if target == 'macos' else destination
    shutil.copytree(ROOT / 'packages/showrunner-obs-overlay/dist/obs-overlay', binary_directory / 'obs-overlay')
    if not (binary_directory / 'obs-overlay/overlay.html').is_file():
        raise RuntimeError('Browser renderer is missing from the staged bundle')
    shutil.copyfile(ROOT / 'LICENSE.md', binary_directory / 'LICENSE.md')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    (binary_directory / 'SOURCE.txt').write_text('ShowRunner source and license: https://github.com/saitatter/sai-showrunner/tree/' + source + '\n', encoding='utf-8')
    output = ROOT / 'release'
    output.mkdir(exist_ok=True)
    prefix = 'ShowRunner-Flutter-' + target + '-' + arch + '-' + args.version
    if target == 'macos':
        run('codesign', '--force', '--deep', '--sign', '-', destination)
        portable = stage / 'portable'
        portable.mkdir()
        shutil.copytree(destination, portable / destination.name, symlinks=True)
        launcher(portable / 'ShowRunner Portable.command', '#!/bin/bash\nset -e\ncd "$(dirname "$0")"\nexport PORTABLE_EXECUTABLE_DIR="$PWD"\nexec "$PWD/ShowRunner.app/Contents/MacOS/ShowRunner" --portable "$@"\n')
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', portable, output / (prefix + '-portable.zip'))
        root = stage / 'installer-root/Applications'
        root.mkdir(parents=True)
        shutil.copytree(destination, root / destination.name, symlinks=True)
        run('pkgbuild', '--root', root.parent, '--identifier', 'io.showrunner.desktop', '--version', native,
            '--install-location', '/', output / (prefix + '-installer.pkg'))
    else:
        portable = stage / 'portable/ShowRunner'
        shutil.copytree(destination, portable, symlinks=True)
        launcher(portable / 'ShowRunner Portable.sh', '#!/bin/sh\nset -eu\ncd "$(dirname "$0")"\nexport PORTABLE_EXECUTABLE_DIR="$PWD"\nexec "$PWD/showrunner_flutter" --portable "$@"\n')
        with tarfile.open(output / (prefix + '-portable.tar.gz'), 'w:gz') as archive:
            archive.add(portable, arcname='ShowRunner')
        root = stage / 'deb'
        shutil.copytree(destination, root / 'opt/showrunner', symlinks=True)
        (root / 'DEBIAN').mkdir()
        deb_version = args.version.replace('-', '~', 1)
        (root / 'DEBIAN/control').write_text(f'Package: showrunner\nVersion: {deb_version}\nArchitecture: amd64\nMaintainer: ShowRunner contributors\nSection: video\nPriority: optional\nDepends: libc6 (>= 2.39), libstdc++6, libgtk-3-0t64, libayatana-appindicator3-1, libsecret-1-0, libmpv2, gnome-keyring, xdg-utils\nDescription: ShowRunner streamer automation desktop\n Visual automation, chat and OBS browser overlays.\n', encoding='utf-8')
        (root / 'usr/bin').mkdir(parents=True)
        launcher(root / 'usr/bin/showrunner', '#!/bin/sh\nexec /opt/showrunner/showrunner_flutter "$@"\n')
        (root / 'usr/share/applications').mkdir(parents=True)
        (root / 'usr/share/applications/io.showrunner.desktop.desktop').write_text('[Desktop Entry]\nType=Application\nName=ShowRunner\nComment=Streaming automation and overlays\nExec=showrunner %U\nIcon=showrunner\nTerminal=false\nCategories=AudioVideo;\nStartupWMClass=io.showrunner.desktop\n', encoding='utf-8')
        icons = root / 'usr/share/icons/hicolor/256x256/apps'
        icons.mkdir(parents=True)
        shutil.copyfile(APP / 'assets/app_icon.png', icons / 'showrunner.png')
        run('dpkg-deb', '--root-owner-group', '--build', root, output / (prefix + '-installer.deb'))
    assets = sorted(output.glob(prefix + '-*'))
    (output / (prefix + '-SHA256SUMS.txt')).write_text(''.join(hashlib.sha256(asset.read_bytes()).hexdigest() + '  ' + asset.name + '\n' for asset in assets), encoding='utf-8')
    print('Packaged ' + target + ' ' + arch + ': ' + ', '.join(asset.name for asset in assets))

if __name__ == '__main__':
    main()
