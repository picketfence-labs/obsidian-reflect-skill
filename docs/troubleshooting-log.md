# Troubleshooting

- A basename-only optimization removed the first bottleneck but left repeated
  link extraction, Git and grep work; a 150-second timeout remained incomplete.
  Select the in-memory implementation with preserved per-path history instead.
- Legacy live measurements that time out provide a time lower bound and partial
  output only. Do not report an exact speedup ratio or zero candidates.
- An empty output with nonzero exit is an error; preserve stderr and exit status.
  Do not grant broad write/network access to make a read-only scan succeed.
- Harness feedback: isolated synthetic fixtures and a pinned legacy checkout
  permit differential checks without exporting consumer data. Semantic Skill
  validation, human review and consumer deployment remain separate.
