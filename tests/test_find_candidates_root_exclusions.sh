#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/find_candidates.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q
git -C "$tmp" config user.name test
git -C "$tmp" config user.email test@example.invalid
mkdir -p "$tmp/02-Areas" "$tmp/05-Daily" "$tmp/06-Templates" "$tmp/.agents/skill-config"

for file in AGENTS.md CLAUDE.md VAULT.md USER.md RULES.md Home.md README.md; do
  printf '# root metadata\n' > "$tmp/$file"
done
printf '%s\n' '---' 'domain: [Test]' '---' '# Topic' > "$tmp/02-Areas/Topic.md"
printf '# daily\n' > "$tmp/05-Daily/2026-09-20.md"
printf '# template\n' > "$tmp/06-Templates/Template.md"
cat > "$tmp/.agents/skill-config/obsidian-reflect.yaml" <<'EOF'
maintenance_heuristics:
  stale_after_days: -1
  stale_max_incoming_links: 99
EOF

git -C "$tmp" add .
git -C "$tmp" commit -qm baseline

output="$(bash "$script" "$tmp" "$tmp/.agents/skill-config/obsidian-reflect.yaml")"
printf '%s' "$output" | grep -F '02-Areas/Topic.md' >/dev/null

for file in AGENTS.md CLAUDE.md VAULT.md USER.md RULES.md Home.md README.md; do
  if printf '%s\n' "$output" | grep -E "^- ${file}(（|$)" >/dev/null; then
    printf 'root metadata file leaked into candidates: %s\n' "$file" >&2
    exit 1
  fi
done

printf 'ok\n'
