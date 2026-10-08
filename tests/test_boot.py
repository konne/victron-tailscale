"""Run with python3 -m unittest discover -s tests -v. Never touches the device."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BootTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.rc = self.base / 'rc.local'
        self.marker = ROOT.name
        self.script = '/data/' + self.marker + '/setup.sh'

    def register(self):
        env = dict(os.environ, RC_LOCAL=str(self.rc), SETUP_SCRIPT=self.script, MARKER=self.marker)
        subprocess.run(['sh', '-ec', '. "$1"; register_boot_hook', 'sh', str(ROOT / 'boot-common.sh')], env=env, check=True)

    def test_hook_replaces_duplicates_before_exit_and_preserves_other_code(self):
        other = 'sh /data/unrelated/setup.sh &\n'
        self.rc.write_text('#!/bin/sh\n' + other + 'exit 0\n# ' + self.marker + '\nsh ' + self.script + '\nsh ' + self.script + ' --boot\n')
        self.rc.chmod(0o644)
        self.register()
        result = self.rc.read_text()
        self.assertEqual(result.count(self.script), 1)
        self.assertLess(result.index(self.script), result.index('exit 0'))
        self.assertIn(other, result)
        self.assertTrue(os.access(self.rc, os.X_OK))
        self.register()
        self.assertEqual(result, self.rc.read_text())

    def test_missing_and_empty_hook(self):
        for existing in (False, True):
            if existing:
                self.rc.write_text('')
            self.register()
            self.assertEqual(self.rc.read_text(), '#!/bin/sh\n# ' + self.marker + '\nsh ' + self.script + ' --boot &\n')

    def test_rootfs_remount_and_failure(self):
        mounts = self.base / 'mounts'
        helper = self.base / 'boot-common.sh'
        helper.write_text((ROOT / 'boot-common.sh').read_text().replace('/proc/mounts', str(mounts)))
        fake_bin = self.base / 'bin'
        fake_bin.mkdir()
        mount = fake_bin / 'mount'
        calls = self.base / 'calls'
        mount.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CALLS"\nexit "$MOUNT_RESULT"\n')
        mount.chmod(0o755)
        env = dict(os.environ, PATH=str(fake_bin) + ':' + os.environ['PATH'], CALLS=str(calls))
        for options, status, expected in [('rw,relatime', '1', 0), ('ro,relatime', '0', 0), ('ro,relatime', '1', 1)]:
            mounts.write_text('/dev/root / ext4 ' + options + ' 0 0\n')
            result = subprocess.run(['sh', '-ec', '. "$1"; prepare_rootfs', 'sh', str(helper)], env=dict(env, MOUNT_RESULT=status), capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stderr)
            if options.startswith('rw'):
                self.assertFalse(calls.exists())
            else:
                self.assertIn('-o remount,rw /', calls.read_text())

    def test_failed_boot_logs_before_rootfs_changes(self):
        install = self.base / 'extension'
        install.mkdir()
        for filename in ['setup.sh', 'boot-common.sh']:
            shutil.copy2(ROOT / filename, install / filename)
        if (ROOT / 'config-template.sh').exists():
            shutil.copy2(ROOT / 'config-template.sh', install / 'config.sh')
        helper = install / 'boot-common.sh'
        helper.write_text(helper.read_text() + '\nprepare_rootfs() { echo "simulated remount failure"; return 1; }\nregister_boot_hook() { echo "unexpected hook edit on boot"; return 1; }\n')
        result = subprocess.run(['sh', str(install / 'setup.sh'), '--boot'], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        log = (install / 'setup.log').read_text()
        self.assertIn('boot=true', log)
        self.assertIn('simulated remount failure', log)
        self.assertIn('exit code 1', log)
        self.assertNotIn('unexpected hook edit', log)
        self.assertNotIn('Setup complete.', log)
        self.assertNotIn('Downloading', log)
        self.assertNotIn('Removing signalk', log)


if __name__ == '__main__':
    unittest.main()
