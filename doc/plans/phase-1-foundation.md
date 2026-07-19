# Phase 1: 基盤整備（Phase 0 残タスク）

## 1. 目的

`bundle gem --test=rspec` で生成したスケルトンのまま残っている TODO・不整合を解消し、以降のフェーズが安全に実装を積み上げられる土台を作る。設計仕様面の対応は overview.md §4（gem 構成）・§11（Rails/capybara 依存の確定）。

## 2. スコープ

### 含むもの

- `capybara-storyboard.gemspec` の TODO メタデータ確定
  - `summary` / `description` / `homepage`
  - `metadata["allowed_push_host"]`
  - `metadata["source_code_uri"]`
  - `metadata["changelog_uri"]`
- ランタイム依存として `add_dependency "capybara"` を追加（overview.md §4: 「依存: capybara（system test 前提）」）。
- sgcop の導入（Gemfile に `sgcop` を追加し、`.rubocop.yml` に `inherit_gem` と `require` を設定）。
- CI（`.github/workflows/main.yml`）の Ruby matrix を、単一固定の `'4.0.5'` から最新2系（3.4 / 4.0）へ整理する。
- README.md のテンプレート文言（`bundle gem` 生成の雛形説明）を削除し、最小限のプレースホルダに整理（本文の充実は P6 で行う。ここでは「テンプレ残骸を残さない」ことのみを目的とする）。
- CHANGELOG.md の Unreleased セクション整備（フォーマットのみ。エントリの充実は各フェーズで随時追記していく運用に揃える）。
- Gemfile.lock を追跡するかどうかの方針決定と、決定に応じた `.gitignore` / リポジトリ状態の整合。

### 含まないもの（Non-goals）

- `lib/capybara/storyboard/*` の実装ロジック（TestHelper・Context・Policy 等）。P2 以降で扱う。
- README.md 本文（導入手順・有効化モデル・移行手順）。P6 で扱う。
- `docs/` 配下（github-actions.md・agent-workflow.md）。P7 で扱う。

## 3. 前提・依存

- 先行フェーズ: なし（最初のフェーズ）。
- 並行可能フェーズ: なし（P2 以降すべてがこのフェーズの完了を前提にする）。
- 外部前提: リポジトリは `bundle gem --test=rspec` のスケルトンそのまま（実装コードなし）であることを確認済み。gemspec の TODO は実在する残タスク。CI の Ruby バージョンは単一固定の `'4.0.5'`（2026-07 時点では実在するバージョンだが matrix が1つしかない）ため、最新2系に整理する残タスク。

## 4. 実装方針

- 責務配置の変更は発生しない（このフェーズはメタデータ・ビルド設定・CI 設定のみを扱う）。
- gemspec のランタイム依存表明を「capybara に依存する」「Rails には直接依存しない」という形に確定する。overview.md §11 にある「Rails 非依存にどこまで寄せるか」は、このフェーズでは **依存表明** （gemspec に `rails` を追加しない、`Rails.root` 前提はコード側の実装挙動として P2 で扱う）という形で一次確定し、実装挙動の詳細は P2 に委ねる。
- sgcop 導入は「Gemfile に追加 → `.rubocop.yml` に `inherit_gem` 設定 → 既存の `AllCops` / `Style/StringLiterals` 等の手書き設定と衝突しない形に整理」という順で進める。sgcop 側の規約と既存手書き設定が競合する場合は sgcop を優先し、手書き設定は sgcop 未カバー分のみ残す。
- CI Ruby matrix は「サポート対象は `required_ruby_version = ">= 3.2.0"`（gemspec 既定）と矛盾しないこと」を基準に、最新2系（3.4 / 4.0）を選定する（4.0 は 2026-05 リリースの実在バージョン）。
- Gemfile.lock の追跡方針は「gem（ライブラリ）なので追跡しない」か「CI 再現性のため追跡する」かを比較し、一般的な Ruby gem の慣行（Lock ファイルは通常 `.gitignore` 対象）に倣うか、明示的に追跡するかをこのフェーズで確定して記録する。

## 5. 変更ファイル

- 変更: `capybara-storyboard.gemspec`
- 変更: `Gemfile`
- 変更: `.rubocop.yml`
- 変更: `.github/workflows/main.yml`
- 変更: `README.md`（テンプレ文言削除・最小プレースホルダ化のみ）
- 変更: `CHANGELOG.md`
- 変更（必要な場合）: `.gitignore`（Gemfile.lock 追跡方針に応じて）
- 新規: なし
- テスト（RSpec）: 新規テストコードの追加は不要（既存の空 spec が通ることを維持）。
- ドキュメント: なし（doc/ 配下の変更はこのフェーズの対象外）。

## 6. 受け入れ条件

- [ ] `gem build capybara-storyboard.gemspec` が成功する。
- [ ] `bundle exec ruby -e "require 'capybara/storyboard'"` 相当の require が成功する（バージョン定数のみでも可）。
- [ ] gemspec に TODO プレースホルダ文字列が一切残っていない。
- [ ] `add_dependency "capybara"` が追加されている。
- [ ] `.rubocop.yml` が sgcop を `inherit_gem` している（strict 版: `ruby/rubocop_strict.yml` と `ruby/rubocop_rspec_strict.yml` を配列指定）。
- [ ] `metadata["rubygems_mfa_required"]` が設定されている（sgcop の `Gemspec/RequireMFA` 対応）。
- [ ] CI の Ruby matrix が最新2系（3.4 / 4.0）で構成されている。
- [ ] CI（spec + sgcop/rubocop）が緑。

## 7. テスト観点

- gemspec のロード自体が失敗しないこと（`gem build` がエラーなく通ること）を確認する。単体テストというよりビルド確認が中心。
- rubocop/sgcop が導入後にエラーなく走ること（違反ゼロである必要はないが、設定ファイル自体が壊れていないこと）。
- CI 上で matrix 全バージョンがセットアップに成功すること（`ruby/setup-ruby` が失敗しない）。
- 単体テストとしての「エッジケース」は本フェーズには存在しない（設定ファイル・メタデータのみのため）。

## 8. リスク・決定事項

このフェーズで確定させる overview.md §11 の決定事項:

- **capybara 依存の表明**: ランタイム依存として `add_dependency "capybara"` を追加することで確定した。
- **Rails を runtime 依存にするか否か**: gemspec には追加しない（Rails 非必須の依存表明）。`Rails.root` を使うかどうかの実装挙動は P2 で確定する。
- **CI 対象 Ruby**: 最新2系（3.4 / 4.0）に確定した。既存の単一固定 `'4.0.5'` を置換。
- **allowed_push_host**: 公開先が未定のため `metadata["allowed_push_host"]` は削除で確定（TODO 文字列を残さない）。将来公開時に再設定する。
- **rubygems_mfa_required**: sgcop の `Gemspec/RequireMFA` が有効なため `metadata["rubygems_mfa_required"] = "true"` を追加で確定。
- **sgcop 導入方法**: rubygems 未公開のため `gem "sgcop", github: "SonicGarden/sgcop", branch: "main"` を Gemfile に追加し、`.rubocop.yml` で strict 版（`ruby/rubocop_strict.yml` + `ruby/rubocop_rspec_strict.yml`）を配列 `inherit_gem` する。`rubocop_rspec_strict.yml` は ruby 側 strict を継承しないため両方の明示指定が必須。手書きの `Style/StringLiterals` 等は削除し `rubocop -a` で既存コードを整形した。
- **Gemfile.lock 追跡**: 非追跡で確定（gem の慣例通り、既存の `.gitignore` の記載を維持）。

リスク:

- sgcop の規約が既存の手書き `.rubocop.yml` 設定（`Style/StringLiterals` 等）と競合し、後続フェーズで追加するコードの lint 結果に影響する可能性がある。導入時点で疎通確認をしておく。
- CI Ruby バージョンの選定を誤ると、後続フェーズで CI が突然赤くなるリスクがあるため、`required_ruby_version` との整合を必ず確認する。

## 9. 参照

- overview.md §4（gem 構成／ファイルツリー案）
- overview.md §11（実装時に確定させる決定事項）
- 既存ファイル: `capybara-storyboard.gemspec` / `Gemfile` / `.rubocop.yml` / `.github/workflows/main.yml` / `README.md` / `CHANGELOG.md`
