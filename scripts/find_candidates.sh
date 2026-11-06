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
# 対象は 00-Inbox〜07-Sources 等のノート本体のみ。ルートのinstruction / adapter / Home、06-Templates（テンプレート）、
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$VAULT_ROOT"

command -v python3 >/dev/null 2>&1 || { echo "エラー: Python 3.9+ が必要です" >&2; exit 1; }
exec python3 -B "$SCRIPT_DIR/vault_scan.py" candidates "$FOLDER_TEMPLATES" "$FOLDER_DAILY" "$FOLDER_LOCAL_REPO" "$STALE_AFTER_DAYS" "$STALE_MAX_INCOMING_LINKS"
