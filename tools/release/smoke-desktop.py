#!/usr/bin/env python3
"""Exercise installed and extracted release packages on ephemeral CI hosts."""
import os
from pathlib import Path
import platform
import subprocess
import tarfile
import tempfile

ROOT = Path(__file__).resolve().parents[2]

def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)

def launch(binary, scenario, data, *, portable_default=False):
    env = dict(os.environ)
    if portable_default:
        env.pop('SHOWRUNNER_USER_DIR', None)
    else:
        env['SHOWRUNNER_USER_DIR'] = str(data)
    command = [str(binary), '--showrunner-smoke=' + scenario]
    log_directory = ROOT / '.tmp/desktop-proof-logs'
    log_directory.mkdir(parents=True, exist_ok=True)
    name = data.parent.name + '-' + data.name + '-' + scenario
    try:
        result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=150)
        output = result.stdout
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ''
        if isinstance(output, bytes): output = output.decode('utf-8', errors='replace')
        for path in (data / 'logs').glob('showrunner.jsonl*'):
            output += '\nApplication log: ' + path.name + '\n' + path.read_text(encoding='utf-8', errors='replace')[-32000:]
        (log_directory / (name + '.log')).write_text(output, encoding='utf-8')
        print(output, flush=True)
        raise
    if result.returncode < 0 and platform.system() == 'Linux':
        # Keep the ordinary run authoritative. A debugger rerun supplies crash
        # evidence only and can never turn the failed package probe green.
        try:
            debug = subprocess.run(['gdb', '--batch', '-ex', 'set pagination off', '-ex', 'run',
                                    '-ex', 'thread apply all bt', '--args', '/bin/bash', *command],
                                   env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, timeout=150)
            output += '\nNative crash backtrace:\n' + debug.stdout
        except (OSError, subprocess.TimeoutExpired) as error:
            output += '\nNative backtrace unavailable: ' + type(error).__name__
    (log_directory / (name + '.log')).write_text(output, encoding='utf-8')
    if result.returncode != 0 or 'Flutter smoke passed: ' + scenario not in output:
        print(output, flush=True)
        raise RuntimeError('Packaged smoke failed: ' + scenario + ' (exit ' + str(result.returncode) + ')')
    print('Packaged smoke passed: ' + scenario, flush=True)
    return result

def smoke(binary, directory):
    for scenario in ('startup', 'first-run', 'automation', 'workflow', 'profile', 'integrations', 'overlays'):
        launch(binary, scenario, directory / scenario)
    # The second run must decrypt the first process's platform-bound secrets.
    launch(binary, 'startup', directory / 'startup')

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
            result = launch(portable / 'ShowRunner Portable.command', 'startup', portable / 'user', portable_default=True)
        else:
            installer = next((ROOT / 'release').glob('*-installer.deb'))
            archive = next((ROOT / 'release').glob('*-portable.tar.gz'))
            run('sudo', 'dpkg', '-i', installer)
            smoke(Path('/usr/bin/showrunner'), work / 'installed')
            with tarfile.open(archive) as bundle:
                bundle.extractall(work, filter='data')
            portable = work / 'ShowRunner'
            smoke(portable / 'ShowRunner Portable.sh', work / 'portable-data')
            result = launch(portable / 'ShowRunner Portable.sh', 'startup', portable / 'user', portable_default=True)
        if result.returncode != 0 or not (portable / 'user/settings').is_dir():
            raise RuntimeError('Portable launcher did not retain its own user data directory')
        print('Installed, portable, encrypted-settings restart and portable data-location proofs passed')

if __name__ == '__main__':
    main()
