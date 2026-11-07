"""명령 대역을 사용한 로컬 회귀 검사. 실제 Ubuntu 서버 검증과 구분한다."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'monitor.sh'


class MonitorTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='b41-tests-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.logs = self.root / 'logs'
        self.logs.mkdir()
        self.script = self.root / 'monitor.sh'
        self.script.write_text(SOURCE.read_text().replace(
            'LOG_DIR="/var/log/agent-app"', f'LOG_DIR="{self.logs}"'))
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'], LC_ALL='C')
        mocks = {
            'pgrep': '[ "${NO_PROCESS:-0}" = 0 ] && echo 12345',
            'ss': '[ "${NO_PORT:-0}" = 0 ] && echo "LISTEN 0 1 0.0.0.0:15034"',
            'sudo': 'echo "Status: ${FIREWALL:-active}"',
            'top': 'echo "%Cpu(s): 25.0 us, 0.0 sy, 0.0 ni, 75.0 id, 0.0 wa"',
            'free': 'echo "Mem: 1000 200 0 0 0 800"',
            'df': 'printf "Filesystem Blocks Used Available Capacity Mounted\\nmock 100 81 19 81%% /\\n"',
            # GNU stat behaviour, also usable on the macOS test host.
            'stat': 'wc -c < "$3" | tr -d "[:space:]"',
        }
        for name, body in mocks.items():
            self.mock(name, body)

    def mock(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/bash\n' + body + '\n')
        path.chmod(0o700)

    def run_monitor(self, **env):
        return subprocess.run(['bash', str(self.script)], env=self.env | env,
                              capture_output=True, text=True, timeout=10)

    def assert_failure(self, result):
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn('[INFO] Log appended:', result.stdout)

    def prepare_rotation(self):
        with (self.logs / 'monitor.log').open('wb') as f:
            f.truncate(10 * 1024 * 1024)
        for i in range(1, 10):
            (self.logs / f'monitor.log.{i}').write_text(f'marker-{i}\n')

    def test_health_failures(self):
        for env in [{'NO_PROCESS': '1'}, {'NO_PORT': '1'}]:
            with self.subTest(env=env):
                self.assert_failure(self.run_monitor(**env))
                self.assertFalse((self.logs / 'monitor.log').exists())

    def test_warnings_continue_and_append(self):
        r = self.run_monitor(FIREWALL='inactive')
        self.assertEqual(r.returncode, 0, r.stderr)
        for text in ['UFW firewall', 'CPU threshold', 'MEM threshold', 'DISK threshold']:
            self.assertIn(text, r.stdout)
        self.assertRegex((self.logs / 'monitor.log').read_text(),
                         r'^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] PID:12345 CPU:25.0% MEM:20.0% DISK_USED:81%\n$')

    def test_collection_failures(self):
        for command in ['top', 'free', 'df']:
            path = self.bin / command
            original = path.read_text()
            for body in ['exit 1', 'echo invalid-output']:
                with self.subTest(command=command, body=body):
                    self.mock(command, body)
                    self.assert_failure(self.run_monitor())
                    self.assertFalse((self.logs / 'monitor.log').exists())
            path.write_text(original)

    def test_append_failure(self):
        (self.logs / 'monitor.log').mkdir()
        r = self.run_monitor()
        self.assert_failure(r)
        self.assertIn('Cannot append log', r.stderr)

    def test_rotation(self):
        self.prepare_rotation()
        r = self.run_monitor()
        self.assertEqual(r.returncode, 0, r.stderr)
        files = list(self.logs.glob('monitor.log*'))
        self.assertEqual(len(files), 10)
        self.assertTrue(all(p.stat().st_size <= 10485760 for p in files))
        self.assertEqual((self.logs / 'monitor.log.1').stat().st_size, 10485760)
        self.assertEqual((self.logs / 'monitor.log.9').read_text(), 'marker-8\n')
        self.assertIn('PID:12345', (self.logs / 'monitor.log').read_text())

    def test_rotation_failures(self):
        for command in ['stat', 'rm', 'mv']:
            with self.subTest(command=command):
                self.prepare_rotation()
                original = (self.bin / command).read_text() if (self.bin / command).exists() else None
                self.mock(command, 'exit 1')
                r = self.run_monitor()
                self.assert_failure(r)
                self.assertIn('[ERROR]', r.stderr)
                if original is None:
                    (self.bin / command).unlink()
                else:
                    (self.bin / command).write_text(original)


if __name__ == '__main__':
    unittest.main()
