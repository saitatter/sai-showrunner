import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('desktop_smoke', Path(__file__).with_name('smoke-desktop.py'))
SMOKE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SMOKE)

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

    def test_portable_probe_removes_explicit_data_override(self):
        result = subprocess.CompletedProcess([], 0, stdout='Flutter smoke passed: startup')
        with patch.dict(os.environ, {'SHOWRUNNER_USER_DIR': '/fixture/override'}), patch.object(SMOKE.subprocess, 'run', return_value=result) as process, contextlib.redirect_stdout(io.StringIO()):
            SMOKE.launch(Path('/fixture/portable'), 'startup', self.root / 'portable/user', portable_default=True)
        self.assertNotIn('SHOWRUNNER_USER_DIR', process.call_args.kwargs['env'])
        self.assertEqual(process.call_args.kwargs['timeout'], 150)

if __name__ == '__main__':
    unittest.main()
