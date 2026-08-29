#!/usr/bin/env bash
# find_candidates.sh
#
# 設計仕様§4「トリガー方法」の「リマインド部分」（wrapup skill等から呼び出される想定）が使う、
# 軽量・機械的なレビュー候補検出スクリプト。LLM推論を一切使わない。
#
# 検出する候補:
#   - 陳腐化候補: 最終更新（gitログ基準。gitで追跡されていなければファイルmtime）から
#     stale_after_days 日超過 かつ 被リンク数（Vault全体での [[wikilink]] 出現回数）が
#     stale_max_incoming_links 件未満のノート
#   - リンク切れ: 本文中の [[wikilink]] が指すファイルがVault内に見つからないもの
#   - 孤立ノート: 被リンク数がゼロのノート（README.mdは除く）
#
# 対象は 00-Inbox〜07-Sources 等のノート本体のみ。06-Templates（テンプレート）、
# 05-Daily（日次ログ。恒常的に被リンクされる性質のノートではないため陳腐化/孤立の対象外）、
# ドット始まりのフォルダ（.git、.obsidian、.claude 等の設定・ツール領域）はノート候補から除外する。
# ただしリンク先の実在チェックでは、テンプレートや添付ファイルも含めたVault全体を対象にする
# （さもないとテンプレートへのリンクが誤ってリンク切れ判定されてしまう）。
#
# コードスパン（`...`）・コードフェンス（```...```）内に書かれた [[wikilink]] は、記法の
# 説明例であって実リンクではないことが多いため、リンク抽出前に取り除く。
#
# Markdownテーブルのセル内では `|` がそのままだと列区切りと解釈されるため、表示名付き
# wikilinkは `[[target\|display]]` のようにパイプをバックスラッシュでエスケープすることがある。
# 表示名を取り除く際はこのエスケープ用バックスラッシュも一緒に消す必要がある
# （`\|` の直前が末尾に残ると、実在するファイルへのリンクが誤って「リンク切れ」判定される）。
#
# 被リンク数カウント用のLINKS_FILEは、リンク先の拡張子を正規化して`.md`無しの形に揃える
# （`[[note.md|display]]` のように拡張子付きでリンク先を書いた場合でも、ノート名基準の
# 被リンクカウントと一致させるため。さもないと拡張子付きでリンクされているノートが
# 誤って「孤立ノート」判定される）。
#
# 出力は標準出力にプレーンテキスト（wrapup skill等がそのままユーザーに提示できる形）。
# ノートの中身を書き換えることは一切しない。
#
# 使い方: ./find_candidates.sh <vault_root> [config.yaml]
#   config.yaml を省略、または存在しない場合は config.yaml.example と同じデフォルト値を使う。

set -euo pipefail

VAULT_ROOT="${1:?Usage: find_candidates.sh <vault_root> [config.yaml]}"
CONFIG_FILE="${2:-}"

# --- 設定読み込み（本スキーマ専用の簡易YAML読み取り。汎用パーサではない） ---
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

FOLDER_TEMPLATES="$(yaml_value "templates" "06-Templates")"
FOLDER_DAILY="$(yaml_value "daily" "05-Daily")"
FOLDER_LOCAL_REPO="$(yaml_value "local_repo" "LOCAL_REPO")"
STALE_AFTER_DAYS="$(yaml_value "stale_after_days" "30")"
STALE_MAX_INCOMING_LINKS="$(yaml_value "stale_max_incoming_links" "2")"

if [[ ! -d "$VAULT_ROOT" ]]; then
  echo "エラー: vault_root が存在しません: ${VAULT_ROOT}" >&2
  exit 1
fi

cd "$VAULT_ROOT"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
NOTES_FILE="${WORKDIR}/notes.txt"          # 候補判定・走査の対象ノート（テンプレート/ドットフォルダ除外）
LINKS_FILE="${WORKDIR}/links.txt"          # NOTES_FILE内の全ノートから抽出したリンク先（1行1件）
ALL_FILES_FILE="${WORKDIR}/all_files.txt"  # リンク先の実在チェック用（Vault全体、ドットフォルダのみ除外）

# コードスパン・コードフェンスを除去してから [[wikilink]] を抽出する（記法の説明例を除外するため）
extract_links() {
  awk 'BEGIN{fence=0} /^```/{fence=!fence; next} fence{next} {print}' "$1" \
    | sed -E 's/`[^`]*`//g' \
    | grep -oE '\[\[[^]]+\]\]' 2>/dev/null || true
}

# ノート候補一覧（ファイル名の空白に対応するためNUL区切りで読む）
: > "$NOTES_FILE"
while IFS= read -r -d '' f; do
  printf '%s\n' "${f#./}" >> "$NOTES_FILE"
done < <(find . -type f -name '*.md' -not -path '*/.*/*' -not -path "./${FOLDER_TEMPLATES}/*" -not -path "./${FOLDER_DAILY}/*" -not -path "./${FOLDER_LOCAL_REPO}/*" -print0)
sort -o "$NOTES_FILE" "$NOTES_FILE"

if [[ ! -s "$NOTES_FILE" ]]; then
  echo "対象ノートが見つかりませんでした。"
  exit 0
fi

# リンク先の実在チェック用: Vault全体（.git・LOCAL_REPOのみ除外。テンプレート・添付ファイル・.claude等の設定ファイルは含む）
# LOCAL_REPOを除外する理由: このファイルはbasenameだけを保存するため、node_modules配下の
# README.md/CHANGELOG.md等の量産ファイルが混ざると、Vault側の本当にリンク切れしているノートが
# 同名のbasenameと偶然一致し「実在する」と誤検出されてしまう（false negative）。
: > "$ALL_FILES_FILE"
while IFS= read -r -d '' f; do
  basename "$f"
done < <(find . -type f -not -path './.git/*' -not -path "./${FOLDER_LOCAL_REPO}/*" -print0) > "$ALL_FILES_FILE"

# 対象ノート中の全wikilinkリンク先（表示名・見出しアンカー・フォルダパスを除去したファイル名部分）
: > "$LINKS_FILE"
while IFS= read -r note; do
  extract_links "$note"
done < "$NOTES_FILE" \
  | sed -E 's/^!?\[\[//; s/\]\]$//; s/\\?\|.*$//; s/#.*$//; s#^.*/##; s/\.md$//' \
  >> "$LINKS_FILE"

# リンク先が実在するか判定する（拡張子なし表記＝ノート名、拡張子あり表記＝ファイル名そのもの、の両方を試す）
link_target_exists() {
  local target="$1"
  grep -Fxq "$target" "$ALL_FILES_FILE" 2>/dev/null && return 0
  grep -Fxq "${target}.md" "$ALL_FILES_FILE" 2>/dev/null && return 0
  return 1
}

echo "## 陳腐化候補（最終更新${STALE_AFTER_DAYS}日超過 かつ 被リンク数${STALE_MAX_INCOMING_LINKS}件未満）"
now_epoch=$(date +%s)
stale_found=0
while IFS= read -r note; do
  last_epoch="$(git log -1 --format=%at -- "$note" 2>/dev/null || true)"
  if [[ -z "$last_epoch" ]]; then
    last_epoch="$(stat -f %m -- "$note" 2>/dev/null || stat -c %Y -- "$note" 2>/dev/null || echo "$now_epoch")"
  fi
  age_days=$(( (now_epoch - last_epoch) / 86400 ))
  if (( age_days > STALE_AFTER_DAYS )); then
    base="$(basename "$note" .md)"
    incoming=$(grep -Fxc "$base" "$LINKS_FILE" || true)
    if (( incoming < STALE_MAX_INCOMING_LINKS )); then
      echo "- ${note}（最終更新${age_days}日前, 被リンク${incoming}件）"
      stale_found=1
    fi
  fi
done < "$NOTES_FILE"
if (( stale_found == 0 )); then echo "- なし"; fi

echo
echo "## リンク切れ候補"
broken_found=0
while IFS= read -r note; do
  while IFS= read -r raw_link; do
    [[ -z "$raw_link" ]] && continue
    target="$(sed -E 's/^!?\[\[//; s/\]\]$//; s/\\?\|.*$//; s/#.*$//' <<<"$raw_link")"
    target_base="$(basename "$target")"
    [[ -z "$target_base" ]] && continue
    if ! link_target_exists "$target_base"; then
      echo "- ${note} -> [[${target}]]（リンク先が見つかりません）"
      broken_found=1
    fi
  done < <(extract_links "$note")
done < "$NOTES_FILE"
if (( broken_found == 0 )); then echo "- なし"; fi

echo
echo "## 孤立ノート候補（被リンク数ゼロ。README.mdは除く）"
orphan_found=0
while IFS= read -r note; do
  [[ "$(basename "$note")" == "README.md" ]] && continue
  base="$(basename "$note" .md)"
  incoming=$(grep -Fxc "$base" "$LINKS_FILE" || true)
  if (( incoming == 0 )); then
    echo "- ${note}"
    orphan_found=1
  fi
done < "$NOTES_FILE"
if (( orphan_found == 0 )); then echo "- なし"; fi
