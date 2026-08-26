#!/usr/bin/env bash
# domain_index.sh
#
# 目的: ClaudeCodeがVaultのファイルを直接読む限り、Obsidian Bases/Dataviewの
# 計算結果（例: Knowledge Mapダッシュボードが実際に返すdomain別グルーピング）は
# 一切見えない（見えるのはクエリの定義だけ）。この構造的な見えなさを埋めるため、
# frontmatterの domain 配列を全ノートから機械的に読み取り、
#   (a) domain → ノート一覧（Knowledge Map相当の全体索引）
#   (b) 指定した1ノートと1つ以上domainが重なる他ノートの一覧
#         （Project→Area/Resource記録直前・Archive移動直前のdomain重複チェック用）
# のいずれかを平文で出力する。LLM推論は一切使わない。
#
# 対応するfrontmatter記法（このVaultの実際の書き方に合わせた簡易パーサ。汎用YAMLパーサではない）:
#   domain: [値1, 値2, ...]
#   domain: []
# frontmatter（先頭の --- 〜 --- ブロック）内の行のみを対象にする（本文中の「domain:」という
# 文字列列挙は誤検出を避けるため見ない）。
#
# 使い方:
#   ./domain_index.sh <vault_root> [config.yaml]                   # (a) 全体のdomain索引
#   ./domain_index.sh <vault_root> [config.yaml] --note <note.md>  # (b) 指定ノートとの重複チェック
#     <note.md> は vault_root からの相対パス
#
# 出力は標準出力にプレーンテキスト。ノートの中身を書き換えることは一切しない。
# macOS標準のBSD grep/awkでも動くよう、-P等のGNU拡張は使わない。

set -euo pipefail

VAULT_ROOT="${1:?Usage: domain_index.sh <vault_root> [config.yaml] [--note <note.md>]}"
shift || true

CONFIG_FILE=""
NOTE_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --note)
      NOTE_ARG="${2:?--note にはノートパスが必要です}"
      shift 2
      ;;
    *)
      if [[ -z "$CONFIG_FILE" ]]; then
        CONFIG_FILE="$1"
      fi
      shift
      ;;
  esac
done

# --- 設定読み込み（find_candidates.sh と同じ簡易YAML読み取り） ---
yaml_value() {
  local key="$1" default="$2" line
  if [[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]]; then
    line="$(grep -E "^[[:space:]]*${key}:" "$CONFIG_FILE" | head -n1 || true)"
    if [[ -n "$line" ]]; then
      sed -E "s/^[[:space:]]*${key}:[[:space:]]*//" <<<"$line" \
        | sed -E 's/#.*$//; s/^"//; s/"[[:space:]]*$//; s/[[:space:]]*$//'
      return
    fi
  fi
  echo "$default"
}

DOMAIN_FIELD="$(yaml_value "domain_field" "domain")"
FOLDER_LOCAL_REPO="$(yaml_value "local_repo" "LOCAL_REPO")"

# IFSの多文字区切りは "${arr[*]}" では先頭1文字しか使われない（bashの既知の仕様）ため、
# ", " 区切りの結合は専用関数で行う
join_comma() {
  local out="" first=1 x
  for x in "$@"; do
    if [[ $first -eq 1 ]]; then out="$x"; first=0; else out="${out}, ${x}"; fi
  done
  printf '%s' "$out"
}

if [[ ! -d "$VAULT_ROOT" ]]; then
  echo "エラー: vault_root が存在しません: ${VAULT_ROOT}" >&2
  exit 1
fi

cd "$VAULT_ROOT"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
PAIRS_FILE="${WORKDIR}/pairs.txt"   # 1行: "<domain>\t<note path>"（タブ区切り）

# frontmatterブロック内の domain 行のみを取り出す
frontmatter_domain_line() {
  awk -v key="$DOMAIN_FIELD" '
    NR==1 && /^---[[:space:]]*$/ { infm=1; next }
    infm && /^---[[:space:]]*$/ { exit }
    infm && $0 ~ "^"key":" { print; exit }
  ' "$1"
}

# "domain: [A, B, C]" / "domain: []" の [...] の中身をカンマ分割してtrimする（1行1値で出力）
split_domain_values() {
  local line="$1" inner
  if [[ "$line" =~ \[(.*)\] ]]; then
    inner="${BASH_REMATCH[1]}"
    [[ -z "$(tr -d '[:space:]' <<<"$inner")" ]] && return
    IFS=',' read -ra parts <<< "$inner"
    for p in "${parts[@]}"; do
      sed -E 's/^[[:space:]]*"?//; s/"?[[:space:]]*$//' <<<"$p"
    done
  fi
}

: > "$PAIRS_FILE"
while IFS= read -r -d '' f; do
  note="${f#./}"
  line="$(frontmatter_domain_line "$note" || true)"
  [[ -z "$line" ]] && continue
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    printf '%s\t%s\n' "$d" "$note" >> "$PAIRS_FILE"
  done < <(split_domain_values "$line")
done < <(find . -type f -name '*.md' -not -path '*/.*/*' -not -path "./${FOLDER_LOCAL_REPO}/*" -print0)

if [[ -n "$NOTE_ARG" ]]; then
  # --- (b) 指定ノートとの重複チェック ---
  if [[ ! -f "$NOTE_ARG" ]]; then
    echo "エラー: 対象ノートが見つかりません: ${NOTE_ARG}" >&2
    exit 1
  fi
  target_line="$(frontmatter_domain_line "$NOTE_ARG" || true)"
  echo "## 対象ノート: ${NOTE_ARG}"
  if [[ -z "$target_line" ]]; then
    echo "domainが設定されていません（対象外）。"
    exit 0
  fi
  target_domains=()
  while IFS= read -r d; do
    target_domains+=("$d")
  done < <(split_domain_values "$target_line")
  if [[ "${#target_domains[@]}" -eq 0 ]]; then
    echo "domain: []（空のため重複チェック対象外）。"
    exit 0
  fi
  printf 'domain: [%s]\n\n' "$(join_comma "${target_domains[@]}")"

  echo "## domainが1つ以上重なるノート"
  found=0
  while IFS= read -r other_note; do
    [[ "$other_note" == "$NOTE_ARG" ]] && continue
    overlap=()
    for d in "${target_domains[@]}"; do
      if awk -F'\t' -v dd="$d" -v nn="$other_note" '$1==dd && $2==nn {found=1} END{exit !found}' "$PAIRS_FILE"; then
        overlap+=("$d")
      fi
    done
    if [[ "${#overlap[@]}" -gt 0 ]]; then
      echo "- ${other_note}（重複: $(join_comma "${overlap[@]}")）"
      found=1
    fi
  done < <(cut -f2 "$PAIRS_FILE" | sort -u)
  if (( found == 0 )); then
    echo "- なし"
  fi
else
  # --- (a) 全体のdomain索引 ---
  echo "## Domain索引（${DOMAIN_FIELD} → ノート一覧。Knowledge Map相当の全体像）"
  if [[ ! -s "$PAIRS_FILE" ]]; then
    echo "（${DOMAIN_FIELD}が設定されたノートが見つかりませんでした）"
    exit 0
  fi
  while IFS= read -r d; do
    echo
    echo "### ${d}"
    awk -F'\t' -v dd="$d" '$1==dd {print $2}' "$PAIRS_FILE" | sort -u | sed 's/^/- /'
  done < <(cut -f1 "$PAIRS_FILE" | sort -u)
fi
