# obsidian-reflect-skill

Obsidian VaultのPARA構成ノートに対して、Reflect（関連発見・MOC更新提案）とReweave（既存ノートへの接続追加・claim更新提案）を行うClaude Code Skillを実装するリポジトリ。

## 設計仕様ドキュメント（実装を始める前に必ず読むこと）
このSkillの上流設計は、開発者のObsidian Vault（Picketfence Labs）内のProjectで完結している。以下のファイルに、スコープ・非スコープ・安全設計・トリガー方法・出力フォーマット・README下書きなどが確定済みの内容としてまとまっている:

```
/Users/shinichi.hashitanikonghq.com/picketfence-labs/04-Archive/2026-08_Ars-Contextaプロセスへの移行検討/notes/2026-08-23_自作Skill設計仕様書（PhaseA）.md
```
（元のProjectは開発完了に伴い`04-Archive`へ移動済み。継続的な知見蓄積は`02-Areas/Repos/obsidian-reflect-skill.md`側で行われている）

このパスは`~/.claude/settings.json`の`permissions.additionalDirectories`経由で既にアクセス可能なはず（新規セッションで`/memory`により確認できる）。実装方針に疑問が生じた場合、まずこのドキュメント（および同じProject内の関連調査メモ）を参照すること。

## このリポジトリの位置づけ
- **本Vault共通ポリシー**（PARAフォルダ構成、`domain`配列frontmatter、`[[wikilink]]`接続、Git管理）を前提に実装する。特定Vault固有の情報（絶対パス・個人情報・実データ）はハードコードしない
- 完成後はユーザースコープ `~/.claude/skills/obsidian-reflect/` に配置され、複数のVaultで共通利用される想定
- GitHubで公開する前提のリポジトリ

## 技術スタック
- Claude Code Skill（`SKILL.md`）＋ 補助スクリプト（bash/python想定）
- 依存確定後、`.claude/settings.json`の権限分割・LSP等の要否をここに追記する

## 開発の進め方
1. 設計仕様ドキュメントを読み、`SKILL.md`のスケルトンを本実装に仕上げる
2. `config.yaml.example`のスキーマを固め、Vaultごとの差し替え可能性を検証する
3. 機械的チェック（リンク切れ・孤立ノート検出）を補助スクリプトとして実装する
4. 実際のVault（Picketfence Labs）を対象にPoCを行い、`00-Inbox/YYYY-MM-DD_reflect-proposals.md`が正しく生成されるか確認する
5. **開発が完了しcommitしたら、セッション終了時に必ず開発ナレッジをVault側へ書き出す。** 手順:
   1. `/Users/shinichi.hashitanikonghq.com/picketfence-labs/06-Templates/External Repo Knowledge Handoff Template.md`を読む（設計仕様ドキュメントと同じ`additionalDirectories`経由でアクセス可能）
   2. そのテンプレートに沿って、実装中に得た学び・ハマりどころ（設定ファイルのスキーマ判断、機械的チェックのエッジケース対応、有効だったプロンプトパターン等）をまとめる
   3. `/Users/shinichi.hashitanikonghq.com/picketfence-labs/00-Inbox/YYYY-MM-DD_obsidian-reflect-skill-knowledge.md`として書き出す（`YYYY-MM-DD`はその日の日付。この絶対パスへの書き込みも`additionalDirectories`経由で可能）
   4. 書き出したファイルパスをユーザーへの完了報告に含める（「commitしました」だけで終わらせない）

   これは`00-Inbox/YYYY-MM-DD_reflect-proposals.md`（Skill自体が生成する機能的な出力）とは別物なので混同しないこと。こちらは「このリポジトリでの開発プロセスそのもの」についてのナレッジ。
