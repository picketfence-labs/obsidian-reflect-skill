#!/usr/bin/env bash
# find_candidates.sh
#
# TODO: 未実装。設計仕様§4「トリガー方法」の「リマインド部分」が呼び出す想定の
# 軽量・機械的なレビュー候補検出スクリプト。LLM推論を一切使わず、以下のような
# 単純なヒューリスティックのみで候補を検出する（Ars Contexta実装を参考）:
#
#   - 陳腐化候補: 最終更新から $STALE_AFTER_DAYS 日超過 かつ 被リンク数が
#     $STALE_MAX_INCOMING_LINKS 未満のノート
#   - リンク切れ: 本文中の [[wikilink]] が指すファイルが存在しないもの
#   - 孤立ノート: 被リンク数がゼロのノート
#
# 出力は標準出力にプレーンテキスト（wrapup skill等がそのままユーザーに提示できる形）。
# ノートの中身を書き換えることは一切しない。
#
# 使い方（想定）: ./find_candidates.sh <vault_root>

set -euo pipefail

VAULT_ROOT="${1:?Usage: find_candidates.sh <vault_root>}"

echo "TODO: not implemented yet. VAULT_ROOT=${VAULT_ROOT}" >&2
exit 1
