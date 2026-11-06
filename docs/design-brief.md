# Large-Vault helper performance

Keep the existing Bash CLI, simple host/legacy config, plain-text sections,
domain matching, exclusions and candidate heuristics while removing repeated
process startup and scans. This changes mechanical helpers; it does not establish
semantic Reflect/Reweave quality or apply any proposal.

The immediate acceptance target is a complete candidate scan within 150 seconds
on the consumer's large live Vault. The consumer retains private input/output and
measurement details; this public repository contains only generic code and
synthetic fixtures. Timed-out work is incomplete, not a successful zero result.

Implement the inventory, one link extraction per note, existence set, incoming
counter and domain overlap in Python 3.9+ standard library. Retain Bash 3.2 entry
points and the existing limited config reader. Preserve exact per-path Git
history semantics; skip history only when the incoming threshold already rules
out a stale candidate. No daemon, network service, package installation or
persistent cache is introduced. Memory is proportional to paths and links.

Return complete stdout only after successful computation. Missing inputs, read,
stat and Git history failures fail with stderr and nonzero exit. Outside Git or
without Git, use mtime as before. Signed integer thresholds are supported;
arithmetic expressions are rejected. Newline/tab file paths were not representable
in the old line/tab intermediates and are now rejected explicitly. No target
note/MOC or consumer Git state is written.

Validation includes the two existing shell tests, threshold/date/config/path and
error/signal tests, differential domain/link spelling tests, synthetic scale with
read-only hashes, and separate private live measurements. Input changes and
incomplete legacy runs limit real-data equivalence claims. Human review/merge,
consumer pin updates, and semantic Reflect remain separate acceptance steps.
