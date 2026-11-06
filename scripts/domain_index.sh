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
# 設定読み取りはBSD/GNU grep/sed対応。索引はPython 3.9+の標準libraryを使用する。

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

if [[ ! -d "$VAULT_ROOT" ]]; then
  echo "エラー: vault_root が存在しません: ${VAULT_ROOT}" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$VAULT_ROOT"

command -v python3 >/dev/null 2>&1 || { echo "エラー: Python 3.9+ が必要です" >&2; exit 1; }
exec python3 -B "$SCRIPT_DIR/vault_scan.py" domains "$FOLDER_LOCAL_REPO" "$DOMAIN_FIELD" "$NOTE_ARG"
