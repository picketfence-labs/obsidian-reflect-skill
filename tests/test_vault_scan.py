"""Requirement-derived CLI/boundary tests; all data is synthetic."""

import hashlib
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('vault_scan', ROOT / 'scripts/vault_scan.py')
SCAN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SCAN)


class VaultTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, name, body='', age=45):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
        stamp = time.time() - age * 86400 - 43200
        os.utime(path, (stamp, stamp))
        return path

    def run_cli(self, name='find_candidates.sh', *args, ok=True, env=None):
        result = subprocess.run(['bash', str(ROOT / 'scripts' / name), str(self.root), *args],
                                capture_output=True, text=True,
                                env=dict(os.environ, LC_ALL='C', **(env or {})), timeout=20)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result

    def test_exclusions_existence_counts_and_read_only(self):
        self.write('02-Areas/孤立 [x].md')
        self.write('02-Areas/Two.md')
        self.write('02-Areas/One.md')
        self.write('02-Areas/README.md')
        self.write('03-Resources/Source.md',
                   '[[Two.md]][[Two#part|alias]][[One]]\n'
                   '[[06-Templates/Template]][[.hidden/Settings.md]][[image.png]]\n'
                   '[[LOCAL_REPO/RepoOnly]][[Missing]][[Missing]]\n'
                   '`[[Inline]]`\n```text\n[[Fence]]\n```\n')
        self.write('06-Templates/Template.md', '[[孤立 [x]]][[Excluded]]')
        self.write('05-Daily/Log.md', '[[孤立 [x]]]')
        self.write('.hidden/Settings.md', '[[孤立 [x]]]')
        self.write('LOCAL_REPO/RepoOnly.md')
        self.write('assets/image.png')
        self.write('AGENTS.md', '[[孤立 [x]]]')
        before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                  for p in self.root.rglob('*') if p.is_file()}
        result = self.run_cli()
        stale, broken, orphan = result.stdout.split('\n\n')
        self.assertNotIn('- 02-Areas/Two.md', stale)
        self.assertIn('02-Areas/One.md（最終更新45日前, 被リンク1件）', stale)
        self.assertIn('- 02-Areas/孤立 [x].md', orphan)
        self.assertNotIn('- 02-Areas/README.md', orphan)
        self.assertEqual(broken.count('[[Missing]]'), 2)
        self.assertIn('[[LOCAL_REPO/RepoOnly]]', broken)
        for text in ('[[image.png]]', '[[.hidden/Settings.md]]', '[[Inline]]', '[[Fence]]'):
            self.assertNotIn(text, broken)
        self.assertEqual(before, {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in self.root.rglob('*') if p.is_file()})

    def test_custom_config_relative_to_caller_and_missing_config(self):
        self.write('02-Areas/Note.md')
        for folder in ('Journal', 'Snippets', 'Repos'):
            self.write(folder + '/Hidden.md')
        config = self.write('custom.yaml', 'daily: "Journal" # comment\n'
                            'templates: "Snippets"\nlocal_repo: "Repos"\n')
        out = self.run_cli('find_candidates.sh', str(config)).stdout
        for folder in ('Journal', 'Snippets', 'Repos'):
            self.assertNotIn('- ' + folder + '/', out)
        self.assertEqual(self.run_cli().stdout,
                         self.run_cli('find_candidates.sh', str(self.root / 'absent.yaml')).stdout)

    def test_stale_threshold_and_future_time(self):
        self.write('02-Areas/Note.md')
        old_cwd = os.getcwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, old_cwd)
        for age, expected in ((30 * 86400, False), (31 * 86400 - 1, False),
                              (31 * 86400, True), (-86401, False)):
            with patch.object(SCAN.time, 'time', return_value=2000000000), \
                    patch.object(SCAN, 'last_update', return_value=2000000000 - age):
                out = SCAN.candidates(['06-Templates', '05-Daily', 'LOCAL_REPO', '30', '2'])
                self.assertEqual('（最終更新31日前' in out, expected)

    def git(self, *args, env=None):
        return subprocess.run(['git', '-C', str(self.root), *args], check=True,
                              capture_output=True, text=True,
                              env=dict(os.environ, **(env or {}))).stdout.strip()

    def test_git_author_date_untracked_mtime_and_rename(self):
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.write('02-Areas/Tracked.md', age=0)
        self.git('add', '.')
        stamp = str(int(time.time()) - 45 * 86400 - 43200) + ' +0000'
        self.git('commit', '-qm', 'old author, recent committer', env={'GIT_AUTHOR_DATE': stamp})
        self.write('02-Areas/Untracked.md')
        self.write('02-Areas/Recent.md', age=0)
        out = self.run_cli().stdout.split('\n\n')[0]
        for name in ('Tracked', 'Untracked'):
            self.assertIn(name + '.md（最終更新45日前', out)
        self.assertNotIn('Recent.md', out)
        self.git('mv', '02-Areas/Tracked.md', '02-Areas/Renamed.md')
        self.git('commit', '-qm', 'rename')
        self.assertNotIn('Renamed.md', self.run_cli().stdout.split('\n\n')[0])

    def test_domain_modes_field_grammar_and_exclusions(self):
        self.write('02-Areas/A.md', '---\ndomain: [A, "日本語", A]\n---\n')
        self.write('03-Resources/B.md', '---\ndomain: [Other, A]\n---\n')
        self.write('04-Archive/C.md', '---\ndomain: []\n---\ndomain: [Ignored]\n')
        self.write('06-Templates/T.md', '---\ndomain: [A]\n---\n')
        self.write('.hidden/H.md', '---\ndomain: [Hidden]\n---\n')
        self.write('LOCAL_REPO/R.md', '---\ndomain: [Repo]\n---\n')
        out = self.run_cli('domain_index.sh').stdout
        self.assertEqual(out.count('### A\n'), 1)
        self.assertIn('- 06-Templates/T.md', out)
        for text in ('### Ignored', '### Hidden', '### Repo'):
            self.assertNotIn(text, out)
        out = self.run_cli('domain_index.sh', '--note', '02-Areas/A.md').stdout
        self.assertIn('domain: [A, 日本語, A]', out)
        self.assertIn('B.md（重複: A, A）', out)
        self.assertNotIn('- 02-Areas/A.md', out)
        self.assertIn('空のため', self.run_cli('domain_index.sh', '--note', '04-Archive/C.md').stdout)
        self.write('NoFront.md', 'domain: [A]\n')
        self.assertIn('設定されていません', self.run_cli('domain_index.sh', '--note', 'NoFront.md').stdout)
        cfg = self.write('custom.yaml', 'domain_field: theme\n')
        self.write('Theme.md', '---\ntheme: [Topic]\n---\n')
        self.assertIn('### Topic', self.run_cli('domain_index.sh', str(cfg)).stdout)

    def test_merge_keeps_path_author_date(self):
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.write('02-Areas/Topic.md', 'base')
        self.git('add', '.')
        self.git('commit', '-qm', 'base')
        original = self.git('symbolic-ref', '--short', 'HEAD')
        self.git('checkout', '-qb', 'side')
        self.write('02-Areas/Topic.md', 'side')
        self.git('add', '.')
        stamp = str(int(time.time()) - 45 * 86400 - 43200) + ' +0000'
        self.git('commit', '-qm', 'side change', env={'GIT_AUTHOR_DATE': stamp})
        self.git('checkout', '-q', original)
        self.write('02-Areas/Other.md', 'main')
        self.git('add', '.')
        self.git('commit', '-qm', 'main change')
        self.git('merge', '--no-ff', '-qm', 'merge side', 'side')
        self.assertIn('Topic.md（最終更新45日前', self.run_cli().stdout.split('\n\n')[0])

    def test_symlinks_do_not_satisfy_links(self):
        self.write('02-Areas/Source.md', '[[Alias.md]]')
        self.write('02-Areas/Real.md')
        (self.root / '02-Areas/Alias.md').symlink_to('Real.md')
        out = self.run_cli().stdout
        self.assertIn('[[Alias.md]]', out.split('\n\n')[1])
        self.assertNotIn('- 02-Areas/Alias.md', out)

    def test_hidden_filename_is_distinct_from_hidden_directory(self):
        self.write('02-Areas/.md')
        self.write('02-Areas/.visible.md')
        self.write('02-Areas/Source.md', '[[.md]][[.visible.md]]')
        out = self.run_cli().stdout
        self.assertIn('- 02-Areas/.md', out.split('\n\n')[2])
        self.assertNotIn('- 02-Areas/.visible.md', out.split('\n\n')[2])

    def test_invalid_inputs_fail_without_success_output(self):
        bad = subprocess.run(['bash', str(ROOT / 'scripts/find_candidates.sh'),
                              str(self.root / 'missing')], capture_output=True)
        self.assertNotEqual(bad.returncode, 0)
        self.assertEqual(bad.stdout, b'')
        self.write('02-Areas/A.md')
        cfg = self.write('invalid.yaml', 'stale_after_days: nonsense\n')
        self.assertEqual(self.run_cli('find_candidates.sh', str(cfg), ok=False).stdout, '')
        self.assertEqual(self.run_cli('domain_index.sh', '--note', 'missing.md', ok=False).stdout, '')
        self.write('02-Areas/bad\nname.md')
        self.assertEqual(self.run_cli(ok=False).stdout, '')

    def test_read_failure_is_not_zero_candidates(self):
        old_cwd = os.getcwd()
        os.chdir(self.root)
        self.addCleanup(os.chdir, old_cwd)
        self.write('02-Areas/A.md')
        with patch.object(SCAN, 'read_note', side_effect=PermissionError('synthetic read failure')):
            with self.assertRaises(PermissionError):
                SCAN.candidates(['06-Templates', '05-Daily', 'LOCAL_REPO', '30', '2'])
        with patch.object(SCAN.os, 'stat', side_effect=OSError('synthetic stat failure')):
            with self.assertRaises(OSError):
                SCAN.last_update('02-Areas/A.md', False)

    def test_git_failure_is_not_mtime_success(self):
        with patch.object(SCAN.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, b'', b'error')):
            with self.assertRaises(RuntimeError):
                SCAN.last_update('02-Areas/Note.md', True)

    def test_signal_interrupts_history_child_without_partial_success(self):
        self.write('02-Areas/A.md')
        bindir = self.root / 'bin'
        bindir.mkdir()
        marker = self.root / 'child.pid'
        git = bindir / 'git'
        git.write_text('#!/usr/bin/env python3\nimport os,sys,time\n'
                       'if sys.argv[1] == "rev-parse": sys.exit(0)\n'
                       'open(os.environ["TEST_CHILD_PID"], "w").write(str(os.getpid()))\n'
                       'time.sleep(30)\n')
        git.chmod(0o755)
        proc = subprocess.Popen(['bash', str(ROOT / 'scripts/find_candidates.sh'), str(self.root)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                env=dict(os.environ, PATH=str(bindir) + os.pathsep + os.environ['PATH'],
                                         TEST_CHILD_PID=str(marker)))
        try:
            until = time.monotonic() + 5
            while not marker.exists() and time.monotonic() < until:
                time.sleep(.02)
            self.assertTrue(marker.exists())
            child = int(marker.read_text())
            proc.send_signal(signal.SIGTERM)
            out, _ = proc.communicate(timeout=5)
            self.assertNotEqual(proc.returncode, 0)
            self.assertEqual(out, b'')
            with self.assertRaises(ProcessLookupError):
                os.kill(child, 0)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()


if __name__ == '__main__':
    unittest.main()
