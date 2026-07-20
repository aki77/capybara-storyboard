# Phase 2: コア移植（挙動パリティ）

## 1. 目的

gist の `AutoScreenshots` concern が持っていた挙動（自動スクリーンショット・手動 `screenshot(label)`・連番ファイル名・出力先構成）を `Capybara::Storyboard::TestHelper` として gem に移植し、RSpec system spec 上で元の gist と同等の挙動を再現する。判定はこの時点ではポリシー抽象を導入せず単一ブール（`SCREENSHOTS` の有無）で行う。対応する仕様は overview.md §3.2（公開 API）・§3.5（テストファイルパス導出）・§3.6（アクション instrumentation）・§3.8（出力レイアウト）。

## 2. スコープ

### 含むもの

- `Capybara::Storyboard::TestHelper` モジュールの新規実装（`included` フックで RSpec の `before`/`after` に登録する設計）。
- クリック系（`click_on` / `click_link` / `click_button`）は **前後両方** を撮影するオーバーライド。
- クリック系以外（`visit` / `fill_in` / `select` / `check` / `uncheck` / `choose` / `attach_file` / `accept_confirm` / `accept_alert`）は **後のみ** 撮影するオーバーライド。
- 手動 `screenshot(label)` API。ENV に関係なく常に撮影可能で、連番カウンタ・出力ディレクトリを自動撮影と共有する。
- 連番ファイル名 `NNN_action_detail.png`（3 桁ゼロ埋め、詳細部分はサニタイズ）の生成。
- 出力先ディレクトリ構成 `tmp/screenshots/{GroupName}/{example_name}/{NNN_action_detail}.png`（overview.md §3.8）。
- 判定は単一ブール（`ENV["SCREENSHOTS"].present?` 相当）。ポリシーオブジェクトへの抽象化は行わない（P3 で行う）。
- RSpec の example メタデータ（`example.metadata[:file_path]` 等）からテストファイルパス・グルーピング識別子を導出するロジック。

### 含まないもの（Non-goals）

- ポリシー抽象（`call(context) -> Boolean` のオブジェクト化）。P3 で導入する。
- `Context` 値オブジェクト。P3 で導入する。
- 対象リスト（`SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS`）による絞り込み。P4 で導入する。
- `Capybara::Storyboard.configure` による設定上書き。P5 で導入する。
- **ページ安定待機**（`document.getAnimations()` + `MutationObserver` によるポーリング、overview.md §3.6）。専用フェーズ（[phase-8-page-stability-wait.md](phase-8-page-stability-wait.md)）に切り出すことを確定した。本フェーズの撮影フックは待機を挟まずに撮影する。
- minitest 対応。§12 の将来課題（本フェーズ・本 gem のスコープ外）。

## 3. 前提・依存

- 先行フェーズ: P1（基盤整備）完了が前提。capybara がランタイム依存として追加済みであること。
- 並行可能フェーズ: なし。
- 外部前提: 被テスト側フレームワークは **RSpec system spec** に確定する（minitest 前提の記述は一切行わない）。`Rails.root` の利用可否は本フェーズで実装挙動として確定する（Rails が存在する環境を前提としてよいと overview.md §4 で判断済み）。

## 4. 実装方針

- `lib/capybara/storyboard/test_helper.rb` に `TestHelper` モジュールを置く。`included do ... end` 内で RSpec の `before`/`after` フックを登録し、per-test の初期化（連番カウンタのリセット、グルーピング識別子・出力ディレクトリの決定）を行う責務を持たせる。
- アクションオーバーライドの責務は `TestHelper` 内に閉じる。個々の Capybara DSL メソッドを `super` 呼び出しでラップし、前後どちらで撮影するかをメソッドごとに固定的に振り分ける（クリック系 = 前後、その他 = 後のみ）。
- 撮影可否の判定ロジックは、この時点では `TestHelper` 内のプライベートメソッド（例: 撮影が有効かどうかを返す 1 メソッド）に閉じ込め、P3 でポリシーオブジェクトに差し替えやすい形（呼び出し口を 1 箇所に集約）にしておく。判定結果は per-test で一度だけ評価してキャッシュし、フックのホットパスでは ENV 読み取りを毎回行わない。
- ファイル名生成（連番ゼロ埋め・アクション名・詳細のサニタイズ）は `TestHelper` 内の専用メソッドに切り出し、手動 `screenshot(label)` と自動撮影の両方から共通利用する。
- テストファイルパスの導出は RSpec の example メタデータから取得する。グルーピング識別子（出力ディレクトリ名）の導出方法（`described_class` を使うか、トップレベル `describe` の文字列を使うか）は本フェーズで確定する（overview.md §11）。
- 出力ルートは本フェーズでは `Rails.root/tmp/screenshots` 固定で実装し、設定可能にする対応（`configure` 経由の `output_dir` 上書き）は P5 に委ねる。
- gem 自身のテスト方針（実ブラウザを使わず Capybara DSL 呼び出しをスタブ/フェイク化するか、ダミー Rails アプリ fixtures を持つか）を本フェーズで確定する（overview.md §8・§11）。

## 5. 変更ファイル

- 新規: `lib/capybara/storyboard/test_helper.rb`
- 変更: `lib/capybara/storyboard.rb`（`require "capybara/storyboard/test_helper"` の追加）
- テスト（RSpec）: `spec/capybara/storyboard/test_helper_spec.rb`（新規）
  - 自動撮影のフック登録・アクション前後撮影・手動 screenshot・ファイル名生成・出力ディレクトリ生成の単体/結合テスト一式。
- ドキュメント: なし（本フェーズでは docs/README 本文には触れない）。

## 6. 受け入れ条件

- [ ] `SCREENSHOTS=1` 環境下で、期待どおりの出力ディレクトリ構造（`tmp/screenshots/{GroupName}/{example_name}/...`）が生成される。
- [ ] ファイル名が `NNN_action_detail.png` 形式（3 桁ゼロ埋め連番・サニタイズ済み詳細）になっている。
- [ ] クリック系アクション（`click_on` / `click_link` / `click_button`）で前後 2 回撮影される。
- [ ] クリック系以外のアクションで後のみ 1 回撮影される。
- [ ] `SCREENSHOTS` 未設定時、自動撮影フックが一切撮影処理を呼ばない（手動 `screenshot(label)` は ENV に関係なく動作する）。
- [ ] 手動 `screenshot(label)` が連番カウンタ・出力ディレクトリを自動撮影と共有する。
- [ ] CI（spec + sgcop/rubocop）が緑。

## 7. テスト観点

- **単体**: ファイル名生成（連番ゼロ埋め・サニタイズ）、グルーピング識別子・example 名からのディレクトリ名導出を、Capybara に依存しない形で検証する。
- **結合**: Capybara DSL 呼び出しをスタブ/フェイク化した上で、「`SCREENSHOTS` 有効時にクリック系は前後 2 回、それ以外は後 1 回、撮影メソッドが呼ばれる」ことを検証する。実ブラウザ結合は最小限のスモークに留める。
- **エッジケース**:
  - `SCREENSHOTS` 未設定時に撮影処理が一切呼ばれないこと（ゼロオーバーヘッドの確認）。
  - 同一テスト内で複数回同じアクションを呼んだ場合の連番の連続性。
  - 詳細文字列に記号・空白・日本語など、ファイル名として不適切な文字が含まれる場合のサニタイズ。
  - example 名やグルーピング識別子に記号が含まれる場合のディレクトリ名サニタイズ。
  - ネストしたサブディレクトリ配置（`spec/system/foo/bar_spec.rb`）は初版のフラット配置前提の範囲内で最低限の確認に留め、網羅検証は将来課題とする（overview.md §3.5・§12）。

## 8. リスク・決定事項

このフェーズで確定した overview.md §11 の決定事項:

- **Rails.root 前提の実装挙動（確定）**: 出力ルート導出を単一メソッド（`default_output_root` 相当）に隔離する。`defined?(Rails)` による防御を行い、Rails が存在する場合は `Rails.root.join("tmp", "screenshots")`、存在しない場合は `Dir.pwd` へのフォールバックとする。この隔離により、テストからは当該メソッドの差し替え/`output_root` 注入で tmpdir に逃がせる。公開 `configure(output_dir)` API は本フェーズでは実装せず P5 に委ねる。
- **gem テスト方式（確定）**: 実ブラウザ・実 Rails を使わず、Capybara DSL をフェイク化したテストハーネス（`FakePage` / `FakeCapybaraDSL` 相当）+ tmpdir 注入で検証する。ダミー Rails アプリ fixtures は持たない。
- **被テスト側 = RSpec system spec 前提（確定）**: minitest には一切対応しない（将来課題として overview.md §12 に既出）。gist（minitest ベース）からの適応として、次の 3 置換を行う: `setup :init_auto_screenshots` → `self.included` 内での `before { ... }` 登録、`self.class.name` → `described_class`（無ければトップレベル `describe` 文字列にフォールバック）、`method_name` → `RSpec.current_example.description`。
- **グルーピング識別子（GroupName）の導出方法（確定）**: `described_class` を優先し、`respond_to?(:name)` を満たさない場合（string subject 等）はトップレベル `describe` の記述文字列にフォールバックする。example 名は `example.description` をサニタイズ後、80 字で切り詰める（空になる場合は `full_description` 等にフォールバック）。
- **ActiveSupport 依存の扱い（確定）**: 被テスト側は Rails アプリ前提（overview.md §4）であり ActiveSupport が実行環境に必ず存在するため、gist の `present?` / `compact_blank` / `truncate` はそのまま利用し、自前ヘルパは作らない。`ActiveSupport::Concern` のみ `self.included` に置換する（フック登録が `before` 1 つで済むため簡潔化目的）。gemspec のランタイム依存表明は変更しない（P1 で確定済みの capybara のみ。ActiveSupport は被テスト側 Rails 経由で存在する前提とし、明示依存は追加しない）。

リスク:

- gist からの移植であるため、gist 側の挙動を正確に再現できているかは実装者の記憶・過去実装に依存する。挙動パリティの検証観点（前後撮影の対象メソッド区分、ファイル名形式）を受け入れ条件に明記して漏れを防ぐ。
- RSpec の example メタデータからのパス導出方式が、ネストしたディレクトリ構成や `shared_examples` 使用時にどう振る舞うかは本フェーズで深掘りせず、将来課題に切り出す判断をしている。想定外の挙動が出た場合はスコープ変更の要否を都度判断する。

> **ページ安定待機の実装フェーズ切り出し（確定済み）**
>
> overview.md §3.6 は撮影直前の **ページ安定待機**（`document.getAnimations()` と `MutationObserver` によるポーリングで DOM/アニメーションの静止を待つ機構）を必須仕様として定義している。この機構の実装は本フェーズ（アクション instrumentation の初回移植）のスコープには含めず、**専用フェーズ（[phase-8-page-stability-wait.md](phase-8-page-stability-wait.md)）に切り出すことを確定した**（§2 Non-goals に明記済み）。
>
> forward pointer:
> - ポーリング間隔・最大試行回数・除外アニメーション名・タイムアウト時挙動の決定事項は、overview.md §11 に「Phase 8 で確定し、設定項目は Phase 5 に反映する」旨を追記済み。パラメータの具体的な確定と実装は Phase 8 で行う。
> - Phase 5（Configuration）のスコープへの設定項目反映も、Phase 8 の実装内容が固まった段階で phase-5-configuration.md 側に反映する。

## 9. 参照

- overview.md §3.2（公開 API）、§3.5（テストファイルパスの導出）、§3.6（アクション instrumentation）、§3.8（出力レイアウト）、§8（テスト戦略）
- gist `AutoScreenshots` concern（移植元。リポジトリ外を参照）
- 既存ファイル: `lib/capybara/storyboard.rb`、`spec/spec_helper.rb`
