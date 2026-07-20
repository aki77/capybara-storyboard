# Phase 5: Configuration

## 1. 目的

`Capybara::Storyboard.configure { |config| ... }` を通じて、出力先ディレクトリとポリシーを利用者側から上書き可能にする。デフォルト値のまま使えば従来どおり動作しつつ、必要な利用者だけが挙動を調整できる余地を作ることが価値。対応する仕様は overview.md §3.2（公開 API）・§3.8（出力レイアウト）。

## 2. スコープ

### 含むもの

- `Capybara::Storyboard.configure` クラスメソッドの追加。
- 設定オブジェクト（`output_dir` の読み書き、ポリシー上書きの読み書き）。
- `TestHelper` および出力先を決定する箇所が設定オブジェクトを参照するようにする配線。
- 未設定時にデフォルト値（出力先: `Rails.root/tmp/screenshots`、ポリシー: P4 までに確定したデフォルトポリシー）へフォールバックする挙動。

### 含まないもの（Non-goals）

- 新しいポリシー種別の追加（ポリシーの実装自体は P3/P4 の責務）。
- 出力レイアウトの構造変更（ディレクトリ階層・ファイル名規則は overview.md §3.8 のまま）。
- 設定の永続化・複数プロファイル切り替えなど、単一プロセス内の一度きりの設定以上の機能。
- README への反映（P6 の責務）。

## 3. 前提・依存

- **先行フェーズ**: P3（ポリシー抽象）に依存する。`policy=` による上書き先である「ポリシーオブジェクト」という概念が P3 で確定していることが前提。
- **並行可能フェーズ**: P4（TargetListPolicy + 対象リスト受け取り）と並行して進めてよい。P5 は「上書きの器」を作るだけで、P4 が確定させる「デフォルトポリシーの中身（Env AND TargetList の合成）」には立ち入らない。
- **統合時の注意**: P3 の時点で「`configure` 未使用時のデフォルト = その時点の最新デフォルトポリシー」という契約が先出しされている前提で進める。P4 と並行開発した場合、P4 側でデフォルトポリシーの合成方法（Env AND TargetList）が変わる可能性があるため、両ブランチ統合時に P5 の「デフォルトへのフォールバック」が P4 の最新デフォルトポリシーを指すよう軽い調整が必要になる。この調整は統合 PR 側で吸収し、P5 単体の受け入れ条件には含めない。
- **外部前提**: Rails 環境（`Rails.root` が利用可能なこと）。初版は Rails/RSpec system spec 前提（overview.md §4）。

## 4. 実装方針

- `configuration.rb` に設定オブジェクトを新設し、次の責務を持たせる。
  - 出力先ディレクトリの保持（未設定時はデフォルト値 `Rails.root/tmp/screenshots` を返す）。
  - ポリシーの保持（未設定時は P3/P4 が確定させたデフォルトポリシーを返す）。
- `Capybara::Storyboard` モジュール側に `configure` クラスメソッドを追加し、設定オブジェクトを yield する。あわせて `Capybara::Storyboard.configuration`（アクセサ）を用意し、`policy` / `policy=`（overview.md §3.2 で定義済みの API）はこの設定オブジェクトへの委譲として実装する方針とする。
- 出力先を決定している箇所（連番ファイル名の書き出し先を組み立てる処理）は、ハードコードされたパスではなく設定オブジェクトの `output_dir` を参照するように変更する。
- 設定の読み込みタイミングは「都度参照」を基本とし、per-test キャッシュ（判定結果のブール値のキャッシュ、overview.md §3.4）とは別の関心事として扱う。設定オブジェクト自体の変更検知や再読込の仕組みは持たない（テスト間で `configure` を呼び直せば次の生成物に反映される程度の単純さでよい）。
- 責務配置の要点: 「何を出力先にするか / どのポリシーを使うか」を決めるのは設定オブジェクトであり、`TestHelper` 側は「設定オブジェクトから値を読んで使うだけ」という一方向の依存に保つ。

## 5. 変更ファイル

- 新規: `lib/capybara/storyboard/configuration.rb`
- 変更: `lib/capybara/storyboard.rb`（`configure` クラスメソッド、`configuration` アクセサ、`policy` / `policy=` の委譲先変更）
- 変更: 出力先パスを組み立てている箇所（P2 で移植された `TestHelper` 内の出力ディレクトリ解決処理、または該当箇所）
- テスト（RSpec）:
  - `spec/capybara/storyboard/configuration_spec.rb`（新規）
  - `spec/capybara/storyboard_spec.rb`（`configure` / `configuration` / `policy` 委譲の既存 spec への追加）
- ドキュメント: このフェーズでは README 更新は行わない（P6 の責務）。

## 6. 受け入れ条件

- [x] `configure { |c| c.output_dir = ... }` で出力先を変更したとき、実際の撮影先ディレクトリがその値に変わることがテストで確認できる。（`session_spec.rb` の「default output root via configuration」で確認）
- [x] `configure { |c| c.policy = ... }` で独自ポリシーを注入したとき、そのポリシーの `call(context)` の戻り値どおりに撮影可否が決まることがテストで確認できる。（`storyboard_spec.rb` の policy 委譲テスト + 既存 `test_helper_spec.rb` の policy 注入で確認）
- [x] `configure` を一度も呼んでいない状態でも、出力先はデフォルト（`Rails.root/tmp/screenshots`）、ポリシーはデフォルトポリシーにフォールバックし、既存の挙動を壊さない。（`configuration_spec.rb` のデフォルト値テストで確認）
- [x] P4 のデフォルトポリシー（Env AND TargetList の合成）と統合した状態で、`configure` 未使用時の挙動が P4 単独の場合と一致する（競合しない）。（既存 `.policy default composition` block が無改修で緑）
- [x] CI（spec + sgcop/rubocop）が緑。（87 examples 0 failures / 20 files no offenses）

## 7. テスト観点

- **単体**: 設定オブジェクト単体で、`output_dir` の getter/setter、未設定時のデフォルト値、`policy` の getter/setter、未設定時のデフォルトポリシーへのフォールバックを検証する。
- **結合**: `configure` ブロックを通した設定変更が、実際に `TestHelper` 経由の撮影先・撮影可否判定に反映されることを検証する。
- **エッジケース**:
  - `configure` を複数回呼んだ場合、後勝ちで値が上書きされること。
  - `output_dir` に相対パス・絶対パスの両方を渡した場合の扱い（既存の出力先解決ロジックとの整合）。
  - `policy=` に渡すオブジェクトが `call(context)` に応答する最小限のインターフェースであれば動作すること（P3 で定義したポリシーの契約を満たせば、gem 内蔵クラス以外でも注入できることの確認）。
  - テスト間で `configuration` の状態が漏れないこと（spec 内で `before`/`after` によるリセットが必要かどうかの検討を含む）。

## 8. リスク・決定事項

- このフェーズ固有の決定事項は overview.md §11 のリストには含まれない（§11 の決定事項はいずれも P1/P2/P4 で確定済み）。
- リスクとして、P4 と並行開発した際にデフォルトポリシーの参照先がずれる可能性がある（§3 に記載のとおり）。このリスクは統合 PR 側で解消する運用とし、P5 の実装自体はデフォルトポリシーの中身に関知しない疎結合な設計とすることでリスクを小さくする。

## 9. 参照

- overview.md §3.2（公開 API: `configure` / `policy` / `policy=`）
- overview.md §3.4（ポリシー抽象・デフォルトポリシー）
- overview.md §3.8（出力レイアウト・`output_dir` の位置づけ）
- overview.md §4（gem 構成: `lib/capybara/storyboard/configuration.rb`）
- [phase-3-policy-env.md](phase-3-policy-env.md)（ポリシー抽象の確定内容）
- [phase-4-target-list.md](phase-4-target-list.md)（デフォルトポリシーの合成方法の確定内容）
