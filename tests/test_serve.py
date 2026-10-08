"""Service reconciliation regressions, using a fake CLI and no network."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SERVICES = '\n|https+insecure://localhost:443|/\nnodered|https+insecure://localhost:1881|/\nui|https+insecure://localhost:1881|/ui\n'


class ServeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.state = self.base / 'state.json'
        self.calls = self.base / 'calls.jsonl'
        cli = self.base / 'tailscale'
        cli.write_text('#!' + sys.executable + '\n' + '''import json, os, sys
from pathlib import Path
args = sys.argv[1:]
state_file = Path(os.environ['STATE'])
state = json.loads(state_file.read_text())
with open(os.environ['CALLS'], 'a') as f:
    f.write(json.dumps(args) + '\\n')
if args[0] != 'serve':
    sys.exit(9)
if 'status' in args:
    # Match Tailscale 1.104.1: parent --service does not filter this output.
    print('\\n'.join(state['routes'].values()))
    sys.exit(0)
service = next(a.split('=', 1)[1] for a in args if a.startswith('--service='))
if service == os.environ.get('FAIL_SERVICE'):
    print('simulated service failure', file=sys.stderr)
    sys.exit(1)
state['routes'][service] = args[-1]
if service not in state['advertised']:
    state['advertised'].append(service)
state_file.write_text(json.dumps(state))
print('This machine is configured as a service host for ' + service + ', but approval from an admin is required.')
''')
        cli.chmod(0o755)

    def run_services(self, routes=None, advertised=None, fail=''):
        self.state.write_text(json.dumps({'routes': routes or {}, 'advertised': advertised or []}))
        env = dict(os.environ, PATH=str(self.base) + ':' + os.environ['PATH'], STATE=str(self.state), CALLS=str(self.calls), DEVICE_NAME='camper', SERVICES=SERVICES, FAIL_SERVICE=fail)
        return subprocess.run(['sh', '-ec', '. "$1"; log() { printf "%s\\n" "$*"; }; configure_services; echo "Setup complete."', 'sh', str(ROOT / 'serve-common.sh')], env=env, text=True, capture_output=True)

    def test_editor_backend_does_not_hide_missing_dashboard(self):
        editor = 'https+insecure://localhost:1881/'
        result = self.run_services({'svc:camper-nodered': editor}, ['svc:camper-nodered'])
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(self.state.read_text())
        self.assertEqual(state['routes']['svc:camper-nodered'], editor)
        self.assertEqual(state['routes']['svc:camper-ui'], editor + 'ui')
        self.assertEqual(state['routes']['svc:camper'], 'https+insecure://localhost:443/')
        self.assertIn('svc:camper-ui', state['advertised'])
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(len(calls), 3)
        self.assertTrue(all('--https=443' in call and '--bg' in call for call in calls))

    def test_existing_route_is_readvertised(self):
        result = self.run_services({'svc:camper-ui': 'https+insecure://localhost:1881/ui'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('svc:camper-ui', json.loads(self.state.read_text())['advertised'])

    def test_changed_dashboard_path_is_applied(self):
        result = self.run_services({'svc:camper-ui': 'https+insecure://localhost:1881/old'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.state.read_text())['routes']['svc:camper-ui'], 'https+insecure://localhost:1881/ui')

    def test_approval_notice_is_not_discarded(self):
        result = self.run_services()
        self.assertEqual(result.returncode, 0)
        self.assertIn('svc:camper-ui, but approval from an admin is required', result.stdout)

    def test_service_failure_prevents_false_success(self):
        result = self.run_services(fail='svc:camper-ui')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('ERROR: failed to configure svc:camper-ui', result.stdout)
        self.assertIn('simulated service failure', result.stdout)
        self.assertNotIn('Setup complete.', result.stdout)


if __name__ == '__main__':
    unittest.main()
