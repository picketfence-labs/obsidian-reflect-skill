#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="${FIND_CANDIDATES_SCRIPT:-$repo_root/scripts/find_candidates.sh}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/02-Areas" "$tmp/03-Resources" "$tmp/04-Archive/X" \
  "$tmp/05-Daily" "$tmp/06-Templates" "$tmp/LOCAL_REPO" "$tmp/.hidden"
cat > "$tmp/config.yaml" <<'EOF'
maintenance_heuristics:
  stale_after_days: -1
  stale_max_incoming_links: 1
EOF

# Each spelling has its own target: another valid link cannot hide a failure.
targets=(
  '02-Areas/[Private] Relative.md'
  '02-Areas/[Private] Root.md'
  '02-Areas/[Private] Parent.md'
  '02-Areas/[Private] 日本語トラッキング.md'
  '02-Areas/[Private] Extension.md'
  '02-Areas/[Private] Table.md'
  '02-Areas/[Private] Heading.md'
  '02-Areas/[Private] Plain.md'
  '02-Areas/[Private] Embed.md'
  '02-Areas/[Private] Adjacent.md'
  '04-Archive/X/index.md'
  '03-Resources/Ordinary.md'
  '03-Resources/Bracket [example] title.md'
)
for target in "${targets[@]}"; do
  printf '# target\n' > "$tmp/$target"
done
cat > "$tmp/03-Resources/Source.md" <<'EOF'
[[../02-Areas/[Private] Relative|Relative Area]]
[[02-Areas/[Private] Root|Root Area]]
[[../../02-Areas/[Private] Parent|Parent Area]]
[[[Private] 日本語トラッキング|日本語トラッキング]]
[[../02-Areas/[Private] Extension.md|Extension]]
| [[../02-Areas/[Private] Table\|Table Area]] |
[[../02-Areas/[Private] Heading#Section|Heading]]
[[[Private] Plain]]
![[../02-Areas/[Private] Embed]]
[[[Private] Adjacent]][[Ordinary.md]]
| [[../04-Archive/X/index\|ラベル]] |
[[../06-Templates/Template]]
[[../03-Resources/Bracket [example] title]]
[[../05-Daily/Log]]
[[../.hidden/Settings.md]]
[[../LOCAL_REPO/RepoOnly]]
[[../02-Areas/[Private] Missing|Missing Area]]
| [[../02-Areas/[Private] Missing Table.md\|Missing Area]] |
`[[../02-Areas/[Private] Inline]]` `[[Missing Inline]]`
```
[[../02-Areas/[Private] Fence]]
[[Missing Fence]]
```
EOF

# Excluded sources must not contribute backlinks or broken-link candidates.
for folder in 06-Templates 05-Daily LOCAL_REPO .hidden; do
  printf '%s\n' '[[[Private] Excluded Only]]' '[[Missing Excluded]]' \
    > "$tmp/$folder/Excluded.md"
done
for name in Inline Fence 'Excluded Only' Unlinked; do
  printf '# unlinked\n' > "$tmp/02-Areas/[Private] $name.md"
done
printf '# template\n' > "$tmp/06-Templates/Template.md"
printf '# daily\n' > "$tmp/05-Daily/Log.md"
printf '# settings\n' > "$tmp/.hidden/Settings.md"
printf '# repository file\n' > "$tmp/LOCAL_REPO/RepoOnly.md"

output="$(bash "$script" "$tmp" "$tmp/config.yaml")"
stale="$(printf '%s\n' "$output" | awk '/^## 陳腐化/{on=1; next} /^## /{on=0} on')"
broken="$(printf '%s\n' "$output" | awk '/^## リンク切れ/{on=1; next} /^## /{on=0} on')"
orphans="$(printf '%s\n' "$output" | awk '/^## 孤立/{on=1; next} on')"
passed=0
failed=0
assert_contains() {
  local text="$1" expected="$2" label="$3"
  if grep -Fq -- "$expected" <<< "$text"; then
    passed=$((passed + 1))
  else
    printf 'FAIL: %s (missing %s)\n' "$label" "$expected" >&2
    failed=$((failed + 1))
  fi
}
assert_absent() {
  local text="$1" unexpected="$2" label="$3"
  if grep -Fq -- "$unexpected" <<< "$text"; then
    printf 'FAIL: %s (found %s)\n' "$label" "$unexpected" >&2
    failed=$((failed + 1))
  else
    passed=$((passed + 1))
  fi
}

for target in "${targets[@]}"; do
  assert_absent "$orphans" "- $target" "linked target is not orphaned"
  assert_absent "$stale" "- ${target}（" "backlink suppresses stale candidate"
done
assert_contains "$broken" '[[../02-Areas/[Private] Missing]]' 'bracketed broken target'
assert_contains "$broken" '[[../02-Areas/[Private] Missing Table.md]]' 'escaped alias and extension stripped correctly'
assert_contains "$broken" '[[../LOCAL_REPO/RepoOnly]]' 'LOCAL_REPO cannot satisfy target existence'
for unexpected in 'Relative' 'Root' 'Parent' '日本語トラッキング' 'Extension' \
  'Table]]' 'Heading' 'Plain' 'Embed' 'Adjacent' 'index' 'Ordinary' 'Bracket' \
  'Template' 'Log' 'Settings' 'Missing Inline' 'Missing Fence' 'Missing Excluded'; do
  assert_absent "$broken" "$unexpected" 'existing or excluded link is not broken'
done
for name in Inline Fence 'Excluded Only' Unlinked; do
  assert_contains "$orphans" "- 02-Areas/[Private] $name.md" 'excluded link does not prevent orphan'
  assert_contains "$stale" "- 02-Areas/[Private] ${name}.md（" 'excluded link does not prevent stale candidate'
done
for folder in 06-Templates 05-Daily LOCAL_REPO .hidden; do
  assert_absent "$output" "- $folder/" 'excluded folder is not scanned as source or candidate'
done

printf 'wikilinks: %s passed, %s failed\n' "$passed" "$failed"
(( failed == 0 ))
