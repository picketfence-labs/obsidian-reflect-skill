"""Optional differential tests against an explicitly supplied, pinned checkout."""

import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest


CURRENT = Path(__file__).resolve().parents[1]
LEGACY = os.environ.get('LEGACY_SCAN_ROOT')


@unittest.skipUnless(LEGACY, 'set LEGACY_SCAN_ROOT to the baseline checkout')
class LegacyCompatibility(unittest.TestCase):
    def test_domain_and_link_spellings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bodies = [
                '---\ndomain: [A, "日本語", A]\n---\n',
                '--- \ndomain: [ "A" , B , , C,]\n---\n',
                '---\ndomain: []\n---\n',
                '---\ndomain: [ ]\n---\n',
                '---\ndomain: scalar\n---\n',
                'domain: [Outside]\n',
                '---\ndomain: [A]\ndomain: [Ignored]\n---\n',
                '---\ndomain: [\'Single quotes\', lower-case]\n---\n',
                '---\ndomain: [A, B] # comment\n---\n',
                '---\ndomain: [A]\n---\ndomain: [Body]\n',
                '---\r\ndomain: [A, B]\r\n---\r\n',
            ]
            folder = root / '02-Areas'
            folder.mkdir()
            stamp = time.time() - 45 * 86400 - 43200
            for index, body in enumerate(bodies):
                path = folder / f'Note [{index}].md'
                path.write_text(body)
                os.utime(path, (stamp, stamp))
            (folder / 'Links.md').write_text(
                '[[Note [0]]][[02-Areas/Note [1].md|alias]]\n'
                '| [[Note [2]\\|table]] | [[Note [3]#heading]]\n'
                '![[Missing.png]][[#same note]][[dir/]][[.]]\n'
                '`[[inline]]` [[Note [0]]] [[Note [0]]]\n'
                '```python\n[[fenced]]\n```\n[[Missing]]')
            # Baseline GNU stat -f can write filesystem text before failing;
            # keep legacy comparisons on tracked data on both platforms.
            def git(*args, env=None):
                subprocess.run(['git', '-C', str(root), *args], check=True,
                               capture_output=True, env=env)
            git('init', '-q')
            git('config', 'user.name', 'Fixture')
            git('config', 'user.email', 'fixture@example.invalid')
            git('add', '.')
            git('commit', '-qm', 'synthetic baseline',
                env=dict(os.environ, GIT_AUTHOR_DATE=str(int(stamp)) + ' +0000'))
            for script, extra in [('find_candidates.sh', []), ('domain_index.sh', [])] + [
                    ('domain_index.sh', ['--note', f'02-Areas/Note [{n}].md']) for n in range(len(bodies))]:
                outputs = []
                for checkout in (Path(LEGACY), CURRENT):
                    proc = subprocess.run(['bash', str(checkout / 'scripts' / script), str(root), *extra],
                                          capture_output=True, env=dict(os.environ, LC_ALL='C'), timeout=30)
                    self.assertEqual(proc.returncode, 0, proc.stderr)
                    outputs.append(proc.stdout)
                self.assertEqual(outputs[0], outputs[1], (script, extra))


if __name__ == '__main__':
    unittest.main()
