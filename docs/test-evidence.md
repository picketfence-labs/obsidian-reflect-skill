# Helper validation evidence

Baseline: `1ba7f89a8e24a00d016084a65b85ecaba051e4a7`. Data below is generated,
not a consumer Vault export. Local run: macOS arm64, Bash 3.2; Python version is
recorded in the PR. CI checks Linux/Python 3.9 and macOS/Python 3.13 separately.

## Results

- Existing root exclusion shell test: PASS.
- Existing wikilink shell test: 60 passed, 0 failed.
- Thirteen new boundary/error tests: PASS (Git author date vs mtime, rename/merge, thresholds,
  duplicates/exclusions, custom/default config, domains, symlinks, read/stat/Git
  failure, invalid input, and SIGTERM child cleanup with no partial stdout).
- Optional legacy differential test: PASS across full domain index, all target
  modes and wikilink spellings (including CRLF, quoted/empty/duplicate domains).
- `skill-creator` quick_validate: valid. Shell syntax: PASS.

| Synthetic input | Mode | Baseline seconds | Current seconds | Output |
| --- | --- | ---: | ---: | --- |
| 300 notes / 3,000 attachments | candidates | 50.751996 | 0.100450 | byte-identical |
| same | domain index | 7.448998 | 0.095403 | byte-identical |
| same | domain --note | 11.828032 | 0.087914 | byte-identical |
| 4,500 notes / 55,000 attachments | candidates | not run | 0.538657 | 4,500 stale, 4,500 broken, 0 orphan |
| same | domain index | not run | 0.455766 | exit 0 |
| same | domain --note | not run | 0.488190 | exit 0 |

Every synthetic benchmark verified unchanged input content hashes. The large
fixture uses mtime rather than a large Git history, so it does not model Git
history cost. See README for reproducible commands. Live measurements and raw
candidate lists remain private. Timed-out baseline runs are incomplete lower
bounds, not exact speedup ratios. Semantic Reflect/Reweave and human acceptance
are not established by these mechanical checks.

## Review and deployment

Self-verification is complete; independent human review/merge and consumer pin
updates remain separate. No consumer gitlink or machine-global checkout is
updated by this change. Additional Linux/minimum-Python results require CI;
local macOS results must not be presented as cross-platform execution.

The pinned legacy implementation has a GNU stat fallback failure for Git-free
notes. Differential tests use tracked notes, and Linux legacy benchmarks explicitly
report tracked_fixture=true. New-helper mtime behavior is tested independently;
the large current-only scale fixture remains Git-free. See troubleshooting log.
