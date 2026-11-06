#!/usr/bin/env python3
"""Read-only, in-memory helpers for the existing Bash entry points.

Deliberately implements the Skill's small domain/wikilink grammar, not a
general YAML or Markdown parser. No index or cache is written into the Vault.
"""

from collections import Counter, defaultdict
import fnmatch
import locale
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import time


ROOT_METADATA = {'AGENTS.md', 'CLAUDE.md', 'VAULT.md', 'USER.md',
                 'RULES.md', 'Home.md', 'README.md'}


def sorted_text(values):
    # Match the shell's sort under the caller's LC_ALL/LC_COLLATE.
    return sorted(values, key=locale.strxfrm)


def inventory(local_repo):
    """Match find -type f (no symlinks), pruning excluded trees early."""
    paths = []

    def fail(error):
        raise error

    for directory, dirs, files in os.walk('.', onerror=fail):
        dirs[:] = [name for name in dirs
                   if not fnmatch.fnmatchcase(directory + '/' + name + '/',
                                             './' + local_repo + '/*')
                   and directory + '/' + name != './.git']
        for name in files:
            path = directory + '/' + name
            if fnmatch.fnmatchcase(path, './' + local_repo + '/*'):
                continue
            if stat.S_ISREG(os.lstat(path).st_mode):
                if '\n' in path or '\t' in path:
                    raise ValueError('newline/tab in a file path is unsupported')
                paths.append(path[2:])
    return paths


def note_paths(paths, excluded=()):
    return sorted_text(path for path in paths
                       if path.endswith('.md')
                       and not any(part.startswith('.') for part in path.split('/')[:-1])
                       and not any(fnmatch.fnmatchcase('./' + path, './' + folder + '/*')
                                   for folder in excluded))


def read_note(path):
    # Preserve arbitrary bytes, CR and final-line behavior of awk/sed.
    with open(path, encoding='utf-8', errors='surrogateescape', newline='') as stream:
        return stream.read()


def links(text):
    fence = False
    for line in text.split('\n'):
        if line.startswith('```'):
            fence = not fence
            continue
        if fence:
            continue
        line = re.sub(r'`[^`]*`', '', line)
        while '[[' in line:
            line = line.split('[[', 1)[1]
            end = line.find(']]')
            if end < 0:
                break
            if end:
                target = re.split(r'\\?\|', line[:end], maxsplit=1)[0]
                yield target.split('#', 1)[0]
            line = line[end + 2:]


def basename(path):
    # POSIX basename removes trailing slashes; '/' remains '/'.
    return path.rstrip('/').rsplit('/', 1)[-1] if path.rstrip('/') else ('/' if path else '')


def git_available():
    try:
        result = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except FileNotFoundError:
        return False
    return result.returncode == 0


def last_update(path, use_git):
    if use_git:
        # Keep Git's path history simplification, merge and rename semantics.
        # A global --name-only log is not equivalent to log -1 -- <path>.
        result = subprocess.run(['git', 'log', '-1', '--format=%at', '--', path],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            raise RuntimeError('git log failed for ' + path)
        value = result.stdout.strip()
        if value:
            return int(value)
    return int(os.stat(path).st_mtime)


def candidates(args):
    templates, daily, local_repo, stale_days, max_incoming = args
    if not re.fullmatch(r'-?[0-9]+', stale_days) or not re.fullmatch(r'-?[0-9]+', max_incoming):
        raise ValueError('maintenance thresholds must be integers')
    stale_days, max_incoming = int(stale_days), int(max_incoming)
    paths = inventory(local_repo)
    notes = [p for p in note_paths(paths, (templates, daily)) if p not in ROOT_METADATA]
    if not notes:
        return '対象ノートが見つかりませんでした。\n'
    existing = {p.rsplit('/', 1)[-1] for p in paths}
    by_note = {p: list(links(read_note(p))) for p in notes}
    incoming = Counter(target.rsplit('/', 1)[-1].removesuffix('.md')
                       for targets in by_note.values() for target in targets)
    stale, broken, orphan = [], [], []
    now = int(time.time())
    use_git = git_available()
    for note, targets in by_note.items():
        name = note.rsplit('/', 1)[-1]
        # basename <name> .md keeps the name when it is exactly '.md'.
        note_base = name[:-3] if name != '.md' else name
        count = incoming[note_base]
        # The age cannot affect the decision when incoming >= max; skip that
        # history query instead of changing how history itself is interpreted.
        if count < max_incoming:
            delta = now - last_update(note, use_git)
            age = delta // 86400 if delta >= 0 else -((-delta) // 86400)
            if age > stale_days:
                stale.append(f'- {note}（最終更新{age}日前, 被リンク{count}件）')
        for target in targets:
            base = basename(target)
            if base and base not in existing and base + '.md' not in existing:
                broken.append(f'- {note} -> [[{target}]]（リンク先が見つかりません）')
        if name != 'README.md' and count == 0:
            orphan.append('- ' + note)
    sections = [
        (f'## 陳腐化候補（最終更新{stale_days}日超過 かつ 被リンク数{max_incoming}件未満）', stale),
        ('## リンク切れ候補', broken),
        ('## 孤立ノート候補（被リンク数ゼロ。README.mdは除く）', orphan),
    ]
    return '\n\n'.join(title + '\n' + '\n'.join(rows or ['- なし'])
                        for title, rows in sections) + '\n'


def domains_in(text, field):
    rows = text.split('\n')
    if not rows or not re.fullmatch(r'---\s*', rows[0]):
        return None
    for row in rows[1:]:
        if re.fullmatch(r'---\s*', row):
            break
        if re.match('^' + field + ':', row):
            match = re.search(r'\[(.*)\]', row)
            if not match or not match[1].strip():
                return []
            # Bash read drops the final empty field, but retains inner empties.
            values = match[1].split(',')
            if values[-1] == '':
                values.pop()
            return [re.sub(r'"?\s*$', '', re.sub(r'^\s*"?', '', p)) for p in values]
    return None


def domains(args):
    local_repo, field, target = args
    target_values = None
    if target:
        target_values = domains_in(read_note(target), field)
        header = f'## 対象ノート: {target}\n'
        if target_values is None:
            return header + 'domainが設定されていません（対象外）。\n'
        if not target_values:
            return header + 'domain: []（空のため重複チェック対象外）。\n'
    by_domain = defaultdict(set)
    by_note = {}
    for note in note_paths(inventory(local_repo)):
        values = domains_in(read_note(note), field)
        values = [v for v in (values or []) if v]
        if values:
            by_note[note] = set(values)
            for value in values:
                by_domain[value].add(note)
    if target:
        rows = []
        for note in sorted_text(by_note):
            if note == target:
                continue
            overlap = [value for value in target_values if value in by_note[note]]
            if overlap:
                rows.append(f'- {note}（重複: {", ".join(overlap)}）')
        return (header + f'domain: [{", ".join(target_values)}]\n\n'
                + '## domainが1つ以上重なるノート\n' + '\n'.join(rows or ['- なし']) + '\n')
    header = f'## Domain索引（{field} → ノート一覧。Knowledge Map相当の全体像）\n'
    if not by_domain:
        return header + f'（{field}が設定されたノートが見つかりませんでした）\n'
    return header + ''.join('\n### ' + value + '\n'
                            + ''.join('- ' + p + '\n' for p in sorted_text(by_domain[value]))
                            for value in sorted_text(by_domain))


def interrupted(signum, _frame):
    raise SystemExit(128 + signum)


def main():
    if sys.version_info < (3, 9):
        print('エラー: Python 3.9+ が必要です', file=sys.stderr)
        return 1
    locale.setlocale(locale.LC_COLLATE, '')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    mode, *args = sys.argv[1:]
    try:
        output = candidates(args) if mode == 'candidates' else domains(args)
    except (OSError, ValueError, RuntimeError, re.error) as error:
        print('エラー: ' + str(error), file=sys.stderr)
        return 1
    sys.stdout.write(output)
    return 0


if __name__ == '__main__':
    sys.exit(main())
