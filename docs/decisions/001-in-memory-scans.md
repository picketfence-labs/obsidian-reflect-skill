# ADR 001: In-memory scans with exact per-path Git history

Status: implemented; human review pending.

## Evidence and alternatives

The legacy helper repeatedly starts basename for every file, awk/sed per note,
Git per note, and grep per target/candidate. Bash parameter expansion can remove
the first bottleneck but retains the repeated link extraction and scans.
Bash 3.2 also lacks associative arrays for the counters/sets.

An awk-based pipeline could batch links but would retain multiple inventories,
intermediate parsing formats and cross-process joins. Python's standard library
provides sets/counters, one note read, explicit error propagation and testable
boundary behavior at a documented interpreter dependency. A synthetic fixture
with 300 notes and 3,000 attachments completed candidate detection in 0.10 seconds
versus 50.75 seconds for the baseline, with identical output. See test evidence
for scope and limitations; this is not a universal speed guarantee.

A global Git log --name-only read does not preserve Git's path-limited history
simplification, merge and rename behavior. Keep log -1 --format=%at -- <path> for
eligible stale candidates and skip it when incoming >= max. Do not substitute
committer dates or a global history index. Consumer-specific live measurements
remain with that consumer rather than in the public core.

## Decision and consequences

Use a shared Python helper behind both existing Bash CLIs. Prune excluded trees,
extract links once, and use in-memory sets/counters. Retain basename matching,
occurrence counts, source exclusions, hidden/config target existence, code-span/
fence grammar, domain parsing and locale sorting. Add no progress chatter to
stdout and no cache. Preserve the existing no-argument/empty-result text.

Python 3.9+ becomes an explicit dependency. Git startup remains the main cost
for eligible tracked notes, so the 150-second result is measured for one consumer,
not a universal bound for every history. Memory scales with file paths and links.
Operational read failures now fail instead of producing a misleading successful
partial/empty result. Threshold expressions and newline/tab paths are explicitly
rejected. Rollback uses the old consumer pin; no data migration is necessary.
