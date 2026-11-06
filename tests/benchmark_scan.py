#!/usr/bin/env python3
"""Reproducible synthetic scale/equivalence check; emits aggregate JSON only."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def digest(root):
    value = hashlib.sha256()
    for path in sorted(root.rglob('*')):
        if path.is_file():
            value.update(str(path.relative_to(root)).encode())
            value.update(path.read_bytes())
    return value.hexdigest()


def run(script, root, extra, timeout):
    start = time.monotonic()
    result = subprocess.run(['bash', str(script), str(root), *extra], capture_output=True,
                            timeout=timeout, env=dict(os.environ, LC_ALL='C'))
    return dict(seconds=round(time.monotonic() - start, 6), exit=result.returncode,
                bytes=len(result.stdout), sha256=hashlib.sha256(result.stdout).hexdigest(),
                stderr_bytes=len(result.stderr)), result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notes', type=int, default=300)
    parser.add_argument('--attachments', type=int, default=3000)
    parser.add_argument('--legacy-root', type=Path)
    parser.add_argument('--timeout', type=int, default=150)
    args = parser.parse_args()
    if args.notes < 2 or args.attachments < 0:
        parser.error('notes >= 2 and attachments >= 0 required')
    current = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix='reflect-synthetic-') as temp:
        root = Path(temp)
        notes = root / '02-Areas'
        notes.mkdir()
        attachments = root / '04-Archive/attachments'
        attachments.mkdir(parents=True)
        stamp = time.time() - 45 * 86400 - 43200
        for index in range(args.notes):
            path = notes / f'Note {index:05d}.md'
            path.write_text('---\ndomain: [Synthetic, Group' + str(index % 7) + ']\n---\n'
                            + f'[[Note {(index + 1) % args.notes:05d}.md|alias]]\n'
                            + f'[[Missing {index:05d}]]\n`[[Ignored]]`\n')
            os.utime(path, (stamp, stamp))
        for index in range(args.attachments):
            (attachments / f'Attachment {index:05d}.txt').write_text('synthetic\n')
        before = digest(root)
        report = dict(notes=args.notes, attachments=args.attachments, results={})
        for script, extra in [('find_candidates.sh', []), ('domain_index.sh', []),
                              ('domain_index.sh', ['--note', '02-Areas/Note 00000.md'])]:
            key = script + (' --note' if extra else '')
            stats, out = run(current / 'scripts' / script, root, extra, args.timeout)
            assert stats['exit'] == 0 and not stats['stderr_bytes'], stats
            if script == 'find_candidates.sh':
                stale, broken, orphan = out.decode().split('\n\n')
                assert sum(row.startswith('- ') for row in stale.splitlines()) == args.notes
                assert sum(row.startswith('- ') for row in broken.splitlines()) == args.notes
                assert orphan.endswith('- なし\n')
            report['results'][key] = dict(current=stats)
            if args.legacy_root:
                old_stats, old_out = run(args.legacy_root / 'scripts' / script, root, extra, args.timeout)
                report['results'][key]['legacy'] = old_stats
                report['results'][key]['identical'] = out == old_out
                assert old_stats['exit'] == 0 and old_out == out, key
        report['read_only_hash_unchanged'] = before == digest(root)
        assert report['read_only_hash_unchanged']
        print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
