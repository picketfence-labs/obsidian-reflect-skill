# obsidian-reflect-skill

Obsidian VaultのPARA構成ノートを対象に、関連ノートの見落とし発見（Reflect）と既存ノートへの接続・claim更新の提案（Reweave）を行う Claude Code Skill。

[agenticnotetaking/arscontexta](https://github.com/agenticnotetaking/arscontexta) の「6 Rs」パイプラインのうち、LLMの意味的判断が本質的に必要な Reflect / Reweave の発想のみを、既存のPARA運用Vaultに後付けできる形で軽量に再実装したもの。Ars Contexta本体の全面採用（3空間構成へのゼロからの作り直し、`git add -A --no-verify`による無差別auto-commit等）は既存Vault運用と衝突するため見送り、発想のみを移植している。

> **Status: 設計段階（スキャフォールディングのみ）。** `SKILL.md`の本体プロンプトは未実装。設計の経緯・意思決定はこのリポジトリの外部（開発者のObsidian Vault内Project）で管理されている。

## これは何をするか
- 指定したノート（またはフォルダ）について、`domain`等のメタデータや内容から関連する既存ノートを探し、リンク追加やMOC（README/Knowledge Map相当）更新の**提案**を生成する（Reflect相当）
- 既存ノートについて、新しい関連ノートへの接続漏れ、内容の陳腐化・矛盾、タイトル/説明文の改善余地を**提案**する（Reweave相当）
- 提案はすべて `<inboxフォルダ>/YYYY-MM-DD_reflect-proposals.md` に出力される。**ノート本体を直接書き換えることは一切ない**

## これは何をしないか
- ノートの自動書き換え・自動commit・自動push（提案は必ず人間の承認を経てから、人間の手で適用する）
- 本文の事実正確性・論理的整合性のファクトチェック
- 既存Vaultの構成をゼロから作り直すような移行・再構築
- マルチユーザー対応、画像・PDF等の非テキストコンテンツへの対応

## 前提条件（対象Vaultが満たすべき規約）
このSkillは以下の規約に沿ったVaultを前提にする:
- PARA的なフォルダ構成（Inbox / Projects / Areas / Resources / Archive等の分類）
- ノートのfrontmatterに`domain`配列などの分類メタデータを持つ
- `[[wikilink]]`でノート間を接続する
- Gitで管理されている

上記に該当しないVault（フォルダ構成が大きく異なる、frontmatter規約がない等）では、`config.yaml`でのマッピング調整が必要、または現状は動作対象外。

## インストール
1. このリポジトリをclone
2. `~/.claude/skills/obsidian-reflect/` にコピー（またはシンボリックリンク）
3. `config.yaml.example` を参考に、対象Vaultのフォルダ名・frontmatterフィールド名を設定した `config.yaml` を用意する

## 使い方
```
/obsidian-reflect <対象ノートpath または フォルダpath>
```
提案が生成されたら、必ず内容を確認したうえで人間が手動でノートに反映する。自動適用はされない。

### wrapup等のセッション終了フローとの連携（任意）
セッション終了時に軽量な機械的チェック（最終更新日・被リンク数等の閾値ベース）でレビュー候補ノートを検出し、`/obsidian-reflect`の実行を促すリマインドを出す統合も可能（本Skill単体ではなく、Vault側のセッション終了Skillへの追加実装が必要）。

## 設計思想・安全設計
- 提案は必ず人間の承認を経てから適用する（自動適用モードは提供しない）
- 変更提案には次の4つの基準を課す: 変更理由を言語化できるか（Articulation）／実際に改善するか（Improvement）／単一の焦点を保っているか（Coherence）／リンク網を改善するか（Network）
- claimの無断変更、過度なノート分割、根拠のない接続追加、文体の勝手な書き換えは行わない

## ライセンス
MIT License. `LICENSE`参照。
