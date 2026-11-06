# obsidian-reflect-skill

Obsidian VaultのPARA構成ノートを対象に、関連ノートの見落とし発見（Reflect）と既存ノートへの接続・claim更新の提案（Reweave）を行う Claude Code Skill。

[agenticnotetaking/arscontexta](https://github.com/agenticnotetaking/arscontexta) の「6 Rs」パイプラインのうち、LLMの意味的判断が本質的に必要な Reflect / Reweave の発想のみを、既存のPARA運用Vaultに後付けできる形で軽量に再実装したもの。Ars Contexta本体の全面採用（3空間構成へのゼロからの作り直し、`git add -A --no-verify`による無差別auto-commit等）は既存Vault運用と衝突するため見送り、発想のみを移植している。

> **Status: 機械的helperを実装済み。意味的Reflect/Reweave全工程のPoC状況とは区別する。** `SKILL.md`本体と`scripts/find_candidates.sh`は実装済み。設計の経緯・意思決定はこのリポジトリの外部（開発者のObsidian Vault内Project）で管理されている。

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
- Bash 3.2以上、Python 3.9以上（標準libraryのみ）、BSD/GNUのgrep・sed
- Gitで管理されている（補助scriptはGit管理外ならmtimeで判定）

上記に該当しないVault（フォルダ構成が大きく異なる、frontmatter規約がない等）では、`config.yaml`でのマッピング調整が必要、または現状は動作対象外。

## インストール

### Vaultごとにversionを固定する場合（推奨）

1. 対象Vaultの`.agents/skills/obsidian-reflect`へ、このrepositoryをGit submoduleとして追加する
2. Codexは`.agents/skills/`から読み、Claude Codeは`.claude/skills/obsidian-reflect`から同じcheckoutへのrelative symlinkを使う
3. `config.yaml.example`を対象Vaultの`.agents/skill-config/obsidian-reflect.yaml`へコピーし、Vault固有設定を管理する

consumer Vaultのgitlinkが利用versionを固定する。更新はsubmodule commitの変更としてreviewし、rollbackは以前のgitlinkへ戻す。

### machine-globalに利用する場合

1. このrepositoryをcloneする
2. `~/.agents/skills/obsidian-reflect`からcloneへのsymlinkを作る
3. providerが別のSkill directoryを必要とする場合は、そこから同じcloneを参照する
4. `config.yaml.example`を参考に、Skill directoryのgit管理外`config.yaml`を用意する

host Vault設定が存在する場合は、machine-global `config.yaml`より優先される。

## 使い方
```
/obsidian-reflect <対象ノートpath または フォルダpath>
```
提案が生成されたら、必ず内容を確認したうえで人間が手動でノートに反映する。自動適用はされない。未処理項目がある間はInboxに保持し、全項目について採用／非採用／保留、理由、反映先、検証結果を追記した後、`04-Archive/Reflect Proposals/`（`config.yaml`で変更可）へ移す。提案の効果・妥当性を後から評価する履歴として残すため、処理後も削除しない。

### wrapup等のセッション終了フローとの連携（任意）
セッション終了時に軽量な機械的チェック（最終更新日・被リンク数等の閾値ベース）でレビュー候補ノートを検出し、`/obsidian-reflect`の実行を促すリマインドを出す統合も可能（本Skill単体ではなく、Vault側のセッション終了Skillへの追加実装が必要）。

### 推奨トリガー: ナレッジ化・Archive化のタイミング
以下の2つのタイミングで、対象ノートに本Skillを実行することを推奨する。domainタグが重なる他の関連ノート（別Project/Area/Resource）の見落としに気づかないまま知見を確定させてしまう事故を防ぐため:
1. **Projectの知見を`02-Areas`/`03-Resources`へ記録（ナレッジ化）する直前**。知見が恒久化される瞬間であり、本質的にはこちらの方がArchive化時点より重要
2. **Projectを`01-Projects`から`04-Archive`へ移動する直前**。ナレッジ化が漏れていた場合の最終チェック

実例: 2026-08-23、あるProjectのArchive化時にdomainが完全に重なる別の関連Projectの存在に気づけなかったことがあり、この推奨事項を追加した。

## 補助スクリプト: domain索引（Bases/Dataviewの計算結果が見えない問題への対応）
Claude CodeはObsidianのBases/Dataviewが実際に計算した結果（例: Knowledge Mapダッシュボードが返すdomain別グルーピング）を見ることができない（見えるのはクエリの定義だけ）。この構造的な見えなさが原因で、2026-08-23、あるProjectのArchive化時にdomainが完全に重なる別の関連Projectを見落とした実例が発生した。

`scripts/domain_index.sh`は、frontmatterの`domain`配列を全ノートから機械的に読み取り、この見えなさを平文で埋める補助スクリプト（LLM推論は使わない）:
```
./scripts/domain_index.sh <vault_root> [config.yaml]                   # domain→ノート一覧の全体索引
./scripts/domain_index.sh <vault_root> [config.yaml] --note <note.md>  # 指定ノートとdomainが重なる他ノートの一覧
```
「推奨トリガー」（ナレッジ化直前・Archive化直前）のdomain重複チェックは、この`--note`モードを使えば`SKILL.md`側の都度Grepより素早く確認できる。

## 設計思想・安全設計
- 提案は必ず人間の承認を経てから適用する（自動適用モードは提供しない）
- 変更提案には次の4つの基準を課す: 変更理由を言語化できるか（Articulation）／実際に改善するか（Improvement）／単一の焦点を保っているか（Coherence）／リンク網を改善するか（Network）
- claimの無断変更、過度なノート分割、根拠のない接続追加、文体の勝手な書き換えは行わない

## ライセンス
MIT License. `LICENSE`参照。

## 補助scriptの実行・検証

既存のCLIとconfig.yamlの簡易読取形式を維持する。Pythonは列挙・domain/wikilink解析・集合/被リンク集計を一括処理する。ネットワーク、pip install、永続索引、Vaultへの書込みは不要。

```bash
bash scripts/find_candidates.sh /path/to/vault /path/to/host-config.yaml
bash scripts/domain_index.sh /path/to/vault /path/to/host-config.yaml --note 02-Areas/Topic.md
bash -n scripts/find_candidates.sh scripts/domain_index.sh
bash tests/test_find_candidates_root_exclusions.sh
bash tests/test_find_candidates_wikilinks.sh
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
python3 -B tests/benchmark_scan.py --notes 4500 --attachments 55000
```

旧版checkoutとの出力比較（両checkoutは書換えない）:

```bash
LEGACY_SCAN_ROOT=/path/to/pinned-baseline python3 -B -m unittest discover -s tests -p test_legacy_compat.py -v
python3 -B tests/benchmark_scan.py --notes 300 --attachments 3000 --legacy-root /path/to/pinned-baseline
```

標準出力には完了した結果だけを出す。読取・stat・履歴照会の失敗、無効な閾値、非対応の改行/タブ入りpathはstderr＋非ゼロ終了とし、成功0件として扱わない。閾値には整数を指定する。domainは従来どおり先頭frontmatter内の1行配列のみ対応し、汎用YAML parserではない。コード除外も従来の行頭バッククォート3個のfenceと単一バッククォートspanの規則を保つ。

入力はlive filesystemでありsnapshotではない。並行変更時は版・件数・変更影響を記録し、timeoutや部分出力を成功件数にしない。候補検出の被リンク数は対象ノート内の出現回数をbasename単位で数える（同名ノート・重複リンク・自己リンクを統合する従来のheuristic）。最終更新は従来と同じGitのauthor date、追跡履歴がなければmtimeを使う。

実行環境には対象VaultのreadとBash/Python・読取専用Gitの実行権限が必要。hostのsandbox/approvalを維持し、helper用に広い書込み権限を追加しない。手動実行は対象ノート/MOC・consumer VaultのGitを変更しない。

導入はPRの人間review/merge後にconsumerの固定gitlinkを別途更新する。`scripts/vault_scan.py`を含むcheckout全体を配置し、Python版と上記fixtureを確認する。rollbackはconsumerのgitlinkを以前のcommitへ戻す。machine-globalの別cloneはconsumer固定版と独立に管理する。

選定理由・互換性境界は[設計](docs/design-brief.md)、[ADR](docs/decisions/001-in-memory-scans.md)、[検証結果](docs/test-evidence.md)を参照。
