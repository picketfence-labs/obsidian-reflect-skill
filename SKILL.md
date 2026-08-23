---
name: obsidian-reflect
description: PARA構成のObsidian Vault内で、指定したノート（またはフォルダ）についてArs Contextaの「Reflect」（関連発見・MOC更新の提案）と「Reweave」（既存ノートへの接続追加・claim更新の提案）に相当する処理を行う際に使う。ノートを直接書き換えることはなく、提案をVaultのInboxフォルダに出力するだけ。ユーザーが明示的にこのSkillの実行を求めた時のみ使う（自動実行はしない）。
---

# obsidian-reflect（スケルトン・未実装）

> **TODO**: このファイルは設計仕様ドキュメント（下記参照）に基づくスケルトンであり、本体プロンプトはまだ実装されていない。実装時はこの節を削除すること。
>
> 設計仕様の全文:
> `/Users/shinichi.hashitanikonghq.com/Workspace/picketfence-labs/01-Projects/2026-08_Ars-Contextaプロセスへの移行検討/notes/2026-08-23_自作Skill設計仕様書（PhaseA）.md`

## 絶対に守ること（設計仕様§2・§3より。実装が変わってもここは変えない）
- **対象ノートを直接書き換えない**。提案は必ず出力先ファイル（`00-Inbox/YYYY-MM-DD_reflect-proposals.md`相当。`config.yaml`の`proposals`設定を見る）に書き出す
- **git commit/pushを行わない**（このSkillの責務ではない）
- 提案には理由を必ず言語化する（Articulation Test）。根拠のない接続追加・claim変更を提案しない
- 事実正確性・論理的整合性のファクトチェックは行わない（範囲外と明言する）

## 手順（TODO: 詳細化する）
1. `config.yaml`（無ければ`config.yaml.example`のデフォルト）を読み、Vaultのフォルダ構成・frontmatterフィールド名を把握する
2. 引数で指定された対象ノート（またはフォルダ内の各ノート）のfrontmatter（`domain`配列等）と本文を読む
3. Vault内で`domain`が重なる、または内容的に関連しそうな既存ノートを検索する（Grep/Globベース。TODO: 検索戦略を具体化する）
4. 見つかった関連候補について、以下を検討し提案を作成する:
   - Reflect相当: リンク追加・MOC（README/Knowledge Map）更新の提案
   - Reweave相当: 接続追加・陳腐化/矛盾のフラグ・claim先鋭化の提案
5. （任意）`scripts/find_candidates.sh`等の機械的チェック結果があれば提案に含める
6. 提案一覧を`config.yaml`で指定された出力先ファイルにMarkdownとして書き出す。既存の同日ファイルがあれば追記する
7. ユーザーに「提案を書き出した。内容を確認し、必要な変更は手動で反映してほしい」旨を報告する

## 出力フォーマット（案。TODO: 実装時に確定する）
```markdown
---
tags: [inbox]
domain: [Obsidian Reflect Proposal]
created: YYYY-MM-DD
---

# Reflect/Reweave提案（YYYY-MM-DD）

## 対象: <ノートパス>

### 提案1: <種別: Reflect / Reweave>
- **内容**: ...
- **理由（Articulation）**: ...
- **影響を受けるノート**: [[...]]
```
