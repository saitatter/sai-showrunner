import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('desktop_smoke', Path(__file__).with_name('smoke-desktop.py'))
SMOKE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SMOKE)
PACKAGE_SPEC = importlib.util.spec_from_file_location('desktop_package', Path(__file__).with_name('package-desktop.py'))
PACKAGE = importlib.util.module_from_spec(PACKAGE_SPEC)
PACKAGE_SPEC.loader.exec_module(PACKAGE)

class DesktopSmokeDiagnosticsTest(unittest.TestCase):
    def setUp(self):
        scratch = Path(__file__).resolve().parents[2] / '.tmp'
        scratch.mkdir(exist_ok=True)
        self.temporary = tempfile.TemporaryDirectory(prefix='desktop-proof-test-', dir=scratch)
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.root_patch = patch.object(SMOKE, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)

    def test_timeout_retains_stdout_and_structured_application_log(self):
        data = self.root / 'installed/startup'
        (data / 'logs').mkdir(parents=True)
        (data / 'logs/showrunner.jsonl').write_text('{"message":"fixture runtime failure"}', encoding='utf-8')
        error = subprocess.TimeoutExpired('fixture', 150, output=b'fixture bootstrap progress')
        with patch.object(SMOKE.subprocess, 'run', side_effect=error), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(subprocess.TimeoutExpired):
                SMOKE.launch(Path('/fixture/app'), 'startup', data)
        diagnostic = next((self.root / '.tmp/desktop-proof-logs').glob('*.log')).read_text(encoding='utf-8')
        self.assertIn('fixture bootstrap progress', diagnostic)
        self.assertIn('fixture runtime failure', diagnostic)

    def test_debugger_cannot_hide_a_native_crash_after_the_success_marker(self):
        failed = subprocess.CompletedProcess([], -11, stdout='Flutter smoke passed: startup')
        debugger = subprocess.CompletedProcess([], 0, stdout='fixture native stack')
        with patch.object(SMOKE.platform, 'system', return_value='Linux'), patch.object(SMOKE.subprocess, 'run', side_effect=[failed, debugger]) as process, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(RuntimeError, 'exit -11'):
                SMOKE.launch(Path('/fixture/app'), 'startup', self.root / 'installed/startup')
        self.assertEqual(process.call_args_list[1].args[0][0], 'gdb')
        self.assertEqual(process.call_args_list[1].args[0][-3:], ['/bin/bash', str(Path('/fixture/app')), '--showrunner-smoke=startup'])
        diagnostic = next((self.root / '.tmp/desktop-proof-logs').glob('*.log')).read_text(encoding='utf-8')
        self.assertIn('fixture native stack', diagnostic)

    def test_portable_probe_removes_explicit_data_override(self):
        result = subprocess.CompletedProcess([], 0, stdout='Flutter smoke passed: startup')
        with patch.dict(os.environ, {'SHOWRUNNER_USER_DIR': '/fixture/override'}), patch.object(SMOKE.subprocess, 'run', return_value=result) as process, contextlib.redirect_stdout(io.StringIO()):
            SMOKE.launch(Path('/fixture/portable'), 'startup', self.root / 'portable/user', portable_default=True)
        self.assertNotIn('SHOWRUNNER_USER_DIR', process.call_args.kwargs['env'])
        self.assertEqual(process.call_args.kwargs['timeout'], 150)

    def test_macos_cross_build_rejects_a_mislabeled_host_architecture(self):
        arguments = ['package-desktop.py', '--version=2.1.0', '--build=1', '--arch=x64']
        with patch.object(PACKAGE, 'ROOT', self.root), patch.object(PACKAGE, 'APP', self.root / 'app'), patch.object(sys, 'argv', arguments), patch.object(PACKAGE.platform, 'system', return_value='Darwin'), patch.object(PACKAGE.platform, 'machine', return_value='arm64'), patch.object(PACKAGE, 'run') as build, patch.object(PACKAGE.subprocess, 'check_output', return_value='arm64\n'):
            with self.assertRaisesRegex(RuntimeError, 'architecture does not match'):
                PACKAGE.main()
        self.assertIn('ARCHS=x86_64', build.call_args.args)

    def test_linux_rejects_cross_architecture_before_building(self):
        arguments = ['package-desktop.py', '--version=2.1.0', '--build=1', '--arch=arm64']
        with patch.object(sys, 'argv', arguments), patch.object(PACKAGE.platform, 'system', return_value='Linux'), patch.object(PACKAGE.platform, 'machine', return_value='x86_64'), patch.object(PACKAGE, 'run') as build, contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit):
                PACKAGE.main()
        build.assert_not_called()

if __name__ == '__main__':
    unittest.main()
