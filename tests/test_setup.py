"""Exercise backend readiness and error handling with fake installed binaries."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.calls = self.base / 'calls'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        (self.base / 'init.d').mkdir()
        shutil.copy2(ROOT / 'init.d/tailscaled', self.base / 'init.d/tailscaled')
        shutil.copy2(ROOT / 'init.d/tailscaled', self.base / 'installed-init')
        script = (ROOT / 'setup.sh').read_text().replace('/etc/init.d/tailscaled', str(self.base / 'installed-init'))
        (self.base / 'setup.sh').write_text(script)
        (self.base / 'boot-common.sh').write_text('prepare_rootfs() { :; }\n')
        shutil.copy2(ROOT / 'serve-common.sh', self.base / 'serve-common.sh')
        config = (ROOT / 'config-template.sh').read_text().replace('/data/victron-tailscale', str(self.base))
        (self.base / 'config.sh').write_text(config)
        commands = {
            'tailscale': '''echo "$*" >> "$CALLS"
case "$1" in
 version) echo 1.104.1 ;;
 status) echo '{"BackendState":"NoState"}' ;;
 up) echo 'simulated connection timeout'; exit "${UP_RESULT:-0}" ;;
 serve) echo 'route applied' ;;
esac''',
            'tailscaled': ':',
            'pgrep': 'exit 0',
            'jq': 'cat >/dev/null; echo "${BACKEND_STATE:-NoState}"',
        }
        for name, body in commands.items():
            p = self.bin / name
            p.write_text('#!/bin/sh\n' + body + '\n')
            p.chmod(0o755)

    def setup_run(self, **env):
        return subprocess.run(['sh', str(self.base / 'setup.sh'), '--boot-once'],
                              env=dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                                       CALLS=str(self.calls), **env), capture_output=True, text=True, timeout=5)

    def test_connection_failure_propagates_and_does_not_apply_routes(self):
        result = self.setup_run(UP_RESULT='7')
        self.assertEqual(result.returncode, 7)
        calls = self.calls.read_text()
        self.assertIn('--timeout=30s', calls)
        self.assertNotIn('serve ', calls)
        log = (self.base / 'setup.log').read_text()
        self.assertIn('simulated connection timeout', log)
        self.assertIn('exit code 7', log)
        self.assertNotIn('Setup complete.', log)

    def test_existing_running_identity_skips_login_and_applies_all_routes(self):
        result = self.setup_run(BACKEND_STATE='Running')
        self.assertEqual(result.returncode, 0)
        calls = self.calls.read_text().splitlines()
        self.assertFalse(any(line.startswith('up ') for line in calls))
        self.assertEqual(sum(line.startswith('serve ') for line in calls), 3)
        self.assertIn('Setup complete.', (self.base / 'setup.log').read_text())
