#!/usr/bin/env python3
"""Exercise installed and extracted release packages on ephemeral CI hosts."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)

def smoke(binary, directory):
    for scenario in ('startup', 'first-run', 'automation', 'workflow', 'profile', 'integrations', 'overlays'):
        data = directory / scenario
        env = dict(os.environ, SHOWRUNNER_USER_DIR=str(data))
        result = subprocess.run([str(binary), '--showrunner-smoke=' + scenario], env=env,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=150)
        if result.returncode != 0 or 'Flutter smoke passed: ' + scenario not in result.stdout:
            print(result.stdout)
            raise RuntimeError('Packaged smoke failed: ' + scenario)
        print('Packaged smoke passed: ' + scenario)
    # The second run must decrypt the first process's platform-bound secrets.
    result = subprocess.run([str(binary), '--showrunner-smoke=startup'], env=dict(os.environ, SHOWRUNNER_USER_DIR=str(directory / 'startup')),
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=150)
    if result.returncode != 0 or 'Flutter smoke passed: startup' not in result.stdout:
        print(result.stdout)
        raise RuntimeError('Packaged encrypted-settings restart failed')

def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Installer proof is restricted to disposable GitHub Actions hosts')
    with tempfile.TemporaryDirectory(prefix='showrunner-package-', dir=ROOT / '.tmp') as temporary:
        work = Path(temporary)
        if platform.system() == 'Darwin':
            installer = next((ROOT / 'release').glob('*-installer.pkg'))
            archive = next((ROOT / 'release').glob('*-portable.zip'))
            run('sudo', 'installer', '-pkg', installer, '-target', '/')
            smoke(Path('/Applications/ShowRunner.app/Contents/MacOS/ShowRunner'), work / 'installed')
            run('ditto', '-x', '-k', archive, work)
            portable = work / 'portable'
            smoke(portable / 'ShowRunner Portable.command', work / 'portable-data')
            # Prove the launcher itself chooses a writable directory beside the app.
            env = dict(os.environ)
            env.pop('SHOWRUNNER_USER_DIR', None)
            result = subprocess.run([str(portable / 'ShowRunner Portable.command'), '--showrunner-smoke=startup'], env=env, timeout=150)
        else:
            installer = next((ROOT / 'release').glob('*-installer.deb'))
            archive = next((ROOT / 'release').glob('*-portable.tar.gz'))
            run('sudo', 'dpkg', '-i', installer)
            smoke(Path('/usr/bin/showrunner'), work / 'installed')
            with tarfile.open(archive) as bundle:
                bundle.extractall(work, filter='data')
            portable = work / 'ShowRunner'
            smoke(portable / 'ShowRunner Portable.sh', work / 'portable-data')
            env = dict(os.environ)
            env.pop('SHOWRUNNER_USER_DIR', None)
            result = subprocess.run([str(portable / 'ShowRunner Portable.sh'), '--showrunner-smoke=startup'], env=env, timeout=150)
        if result.returncode != 0 or not (portable / 'user/settings').is_dir():
            raise RuntimeError('Portable launcher did not retain its own user data directory')
        print('Installed, portable, encrypted-settings restart and portable data-location proofs passed')

if __name__ == '__main__':
    main()
