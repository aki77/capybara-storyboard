# Phase 6: README + 移行手順

## 1. 目的

導入者（gem を新規に使い始める人・gist の `AutoScreenshots` concern から移行する人）向けに、インストールから有効化、既存利用者の移行までを一気通貫で読める README を整備する。対応する仕様は overview.md §5（有効化モデル）・§9（gist からの移行）。

## 2. スコープ

### 含むもの

- gem のインストール手順。
- `Capybara::Storyboard::TestHelper` を RSpec system spec に include する方法。
- 有効化モデル（overview.md §5 の 3 ケース表）の掲載。
- 前提と割り切り（`spec/system/*_spec.rb` フラット配置前提、ビューのみ変更 PR は初版では非対応であること）の明記。
- gist からの移行手順（`AutoScreenshots` concern 削除 → `TestHelper` include、ENV 名 `SCREENSHOTS` の互換維持、対象リストは opt-in であることの明記）。
- `SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS` を併用した場合は和集合になる仕様の明記。

### 含まないもの（Non-goals）

- CI 連携レシピの詳細（`docs/github-actions.md`）は P7 の責務であり、README では概要と該当ドキュメントへの導線のみ扱う。
- エージェント向けワークフロー（`docs/agent-workflow.md`）の詳細は P7 の責務。
- minitest 向けの記述（初版は RSpec system spec のみ対応。minitest は将来課題であり、本フェーズでも一切記述しない）。
- ポリシーや Configuration の実装詳細の再解説（overview.md の該当節への参照に留める）。

## 3. 前提・依存

- **先行フェーズ**: P4（TargetListPolicy + 対象リスト受け取り）に依存する。有効化モデルの 3 ケース目（選択撮影）と、対象リストの受け渡し口（`SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS`）が確定していることが前提。これらが未確定のまま書くと記述が二転三転するため、P4 完了後に着手する。
- **並行可能フェーズ**: P7（docs/github-actions.md + docs/agent-workflow.md）と並行して進めてよい。README と P7 のドキュメントは参照関係を持つが、相互に実装を必要としないため独立して執筆できる。
- **外部前提**: 最小構成の Rails + RSpec system spec 環境で追試できること（受け入れ条件参照）。

## 4. 実装方針（＝執筆内容）

- **インストール手順**: Gemfile への追加、`bundle install`、RSpec 側の読み込み方法（`spec_helper.rb` / `rails_helper.rb` への require の記載）。
- **TestHelper の include 方法**: RSpec system spec への include 例（`RSpec.configure` での `config.include Capybara::Storyboard::TestHelper, type: :system` のような、system spec 全体への一括 include を基本形として案内する）。
- **有効化モデル**: overview.md §5 の表（無効 / 全撮影 / 選択撮影の 3 ケースと `SCREENSHOTS` ・対象リストの関係）をそのまま README に転記する。表の再定義はせず、overview.md を SSOT として一致させる。
- **前提と割り切り**:
  - `spec/system/*_spec.rb` のフラット配置を主な前提とすること（ネストしたサブディレクトリ配置は将来課題であり、初版でも動作しうるが網羅検証はしていないことを明記）。
  - 「ビューのみ変更で system spec ファイル自体は不変」の PR は対象リスト方式では拾えないという、初版の既知の割り切りを明記する。
- **gist からの移行手順**:
  - `AutoScreenshots` concern を削除し、`Capybara::Storyboard::TestHelper` の include に置き換える差分の書き方。
  - ENV 名 `SCREENSHOTS` は互換維持されており、既存の `SCREENSHOTS=1` 運用はそのまま動作すること。
  - 対象リスト（`SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS`）は新機能であり opt-in、指定しなければ既存挙動（全撮影）のままであること。
- **決定事項の明記**: `SCREENSHOT_TESTS_FILE` と `SCREENSHOT_TESTS` を両方指定した場合は和集合になる仕様を、README の対象リストの節に明記する。

## 5. 変更ファイル

- 変更: `README.md`
- 変更（必要なら）: `CHANGELOG.md`（README 整備に伴う利用者向け変更点があれば追記）
- ドキュメント: 本フェーズの成果物自体が README というドキュメントであるため、追加のドキュメントファイルは作成しない。

## 6. 受け入れ条件（レビュー観点/追試手順）

- [ ] README の手順どおりに、最小構成の Rails + RSpec system spec アプリで「全撮影」（`SCREENSHOTS=1` のみ）が再現できる（レビュアが追試可能）。
- [ ] README の手順どおりに、最小構成の Rails + RSpec system spec アプリで「選択撮影」（`SCREENSHOTS=1` + `SCREENSHOT_TESTS_FILE` または `SCREENSHOT_TESTS`）が再現できる（レビュアが追試可能）。
- [ ] gist の `AutoScreenshots` concern を使っていた想定の移行手順が、差分として明確に読める（削除するもの・追加するものが具体的なコード片レベルで示されている）。
- [ ] `SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS` 併用時の和集合仕様が README に明記されている。
- [ ] minitest 前提の記述が一切含まれていない。
- [ ] CI（rubocop/sgcop を含む）が緑。README 変更が Markdown lint やリンクチェックなど CI 上のドキュメントチェックを壊さない。

## 7. テスト観点（レビュー観点/追試手順）

- **追試手順の切り分け**: 「全撮影」パスと「選択撮影」パスを別々の追試シナリオとして手順化し、レビュアがそれぞれ独立に再現できるようにする。
- **網羅すべきエッジ**:
  - `SCREENSHOTS` 未設定時に何も撮影されないことの確認手順も含める（無効ケースの追試）。
  - 対象リストに存在しないファイルパスを指定した場合、撮影 0 件になることの確認手順。
  - gist からの移行手順を実際に「移行前 → 移行後」の 2 状態で追える形にし、移行前の状態（`AutoScreenshots` concern がある想定）から読んでも迷わないこと。
- **レビュー観点**: overview.md の該当節（§5, §9）と記述内容が矛盾していないか、章立てが README として自然な導線（インストール → 使い方 → 有効化モデル → 移行 → 前提の割り切り）になっているかを確認する。

## 8. リスク・決定事項

- **決定事項**: `SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS` 併用時の和集合仕様は P4 で技術的に確定済みであり、本フェーズではその仕様を README に明記することが決定事項（overview.md §11 のうち「README 明記」の部分を本フェーズで完了させる）。
- **リスク**: P4 で対象リストの受け渡し口の細部（正規化ルールの具体例など）が変わった場合、README の記述も追従が必要になる。README は overview.md の記述を転記する形にとどめ、独自の解釈を書き足さないことでズレのリスクを抑える。

## 9. 参照

- overview.md §5（有効化モデルまとめ）
- overview.md §9（gist からの移行）
- overview.md §3.7（対象集合の渡し方、和集合仕様の根拠）
- [phase-4-target-list.md](phase-4-target-list.md)（対象リスト受け渡し口の確定内容）
- 既存 `README.md`（現状の記述との差分ベースラインとして参照）
- gist `AutoScreenshots` concern（移行元の挙動の参照元）
