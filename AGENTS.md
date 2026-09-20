# Repository instructions

This repository is the canonical public implementation of the `obsidian-reflect` Skill.

Before substantial changes, read `SKILL.md`, `README.md`, and the affected script. Preserve the proposal-only boundary: never edit target notes, apply proposed changes, or commit/push a consumer Vault.

Keep host-specific names, absolute paths, private data, and consumer workflow outside the shared core. Maintain compatibility with the documented host configuration and legacy local `config.yaml` unless a breaking change is explicitly planned.

Validate Skill changes with `skill-creator` `quick_validate.py`. Run `bash -n` and relevant tests for shell changes. Use isolated fixture Vaults rather than live consumer data.
