"""Boot retries, failure propagation and lock lifetime without a real device."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.calls = self.base / 'calls'
        self.env = dict(os.environ, PATH=str(self.base) + ':' + os.environ['PATH'],
                        CALLS=str(self.calls), SETUP_LOCK_FILE=str(self.base / 'lock'),
                        MARKER='test', SETUP_SCRIPT=str(self.base / 'worker'))
        # macOS has no flock CLI; use the same OS flock operation on inherited fd 9.
        self.command('flock', '#!' + sys.executable + '\nimport fcntl, sys\ntry: fcntl.flock(int(sys.argv[-1]), fcntl.LOCK_EX | fcntl.LOCK_NB)\nexcept BlockingIOError: sys.exit(1)\n')
        self.command('sleep', '#!/bin/sh\necho "sleep $1" >> "$CALLS"\n')

    def command(self, name, text):
        p = self.base / name
        p.write_text(text)
        p.chmod(0o755)
        return p

    def run_helper(self, command):
        return subprocess.run(['sh', '-ec', '. "$1"; ' + command, 'sh', str(ROOT / 'boot-common.sh')],
                              env=self.env, capture_output=True, text=True, timeout=5)

    def test_failed_workers_retry_and_preserve_errexit(self):
        self.command('worker', '''#!/bin/sh
set -e
echo "attempt $1" >> "$CALLS"
count=$(grep -c '^attempt' "$CALLS")
if [ "$count" -le 2 ]; then
    false
    echo "ERROR: ignored failure" >> "$CALLS"
fi
''')
        result = self.run_helper('acquire_setup_lock; run_boot_setup')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls.read_text().splitlines(), ['attempt --boot-once', 'sleep 10',
                          'attempt --boot-once', 'sleep 20', 'attempt --boot-once'])
        self.assertIn('completed after 3 attempt(s)', result.stdout)
        self.assertIn('exit 1', result.stdout)

    def test_retry_delay_caps_and_does_not_give_up(self):
        self.command('worker', '''#!/bin/sh
echo attempt >> "$CALLS"
[ "$(grep -c '^attempt' "$CALLS")" -gt 7 ]
''')
        result = self.run_helper('acquire_setup_lock; run_boot_setup')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([line for line in self.calls.read_text().splitlines() if line.startswith('sleep')],
                         ['sleep 10', 'sleep 20', 'sleep 40', 'sleep 80', 'sleep 160', 'sleep 300', 'sleep 300'])

    def test_worker_does_not_inherit_setup_lock(self):
        check = self.command('check.py', '#!' + sys.executable + '\nimport fcntl, sys\ntry: fcntl.fcntl(9, fcntl.F_GETFD)\nexcept OSError: sys.exit(0)\nsys.exit(1)\n')
        self.command('worker', '#!/bin/sh\nexec "' + str(check) + '"\n')
        result = self.run_helper('acquire_setup_lock; run_boot_setup')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('completed after 1 attempt(s)', result.stdout)

    def test_duplicate_skipped_and_lock_released_after_exit(self):
        first = subprocess.Popen(['sh', '-ec', '. "$1"; acquire_setup_lock; echo ready; read line',
                                  'sh', str(ROOT / 'boot-common.sh')], env=self.env,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            self.assertEqual(first.stdout.readline().strip(), 'ready')
            second = self.run_helper('acquire_setup_lock; echo acquired')
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertIn('skipping duplicate', second.stdout)
            self.assertNotIn('acquired', second.stdout)
        finally:
            first.communicate('\n', timeout=5)
        third = self.run_helper('acquire_setup_lock; echo acquired')
        self.assertEqual(third.returncode, 0, third.stderr)
        self.assertIn('acquired', third.stdout)
