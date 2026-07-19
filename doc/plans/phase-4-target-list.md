# Phase 4: TargetListPolicy + 対象リスト受け取り

## 1. 目的

「機構が arm されている（Env）」だけでなく「対象テストファイルに含まれる」という条件を追加できるようにし、GitHub Actions 上で「PR 内で変更のあったシステムテストファイルのみ有効化」するユースケースを実現する。対応する仕様は overview.md §3.4（ポリシー抽象、特に `TargetListPolicy` と合成ポリシー）、§3.7（対象集合の渡し方）、§5（有効化モデルまとめ）。

## 2. スコープ

### 含むもの

- `Capybara::Storyboard::Policies::TargetListPolicy` の新規実装。
  - コンストラクタで対象テストファイルパスの集合（正規化済み）を受け取る。
  - `context.test_file` が集合に含まれれば `true`。
  - 集合が空なら「絞り込みなし」として `true`（後方互換で全撮影）。
- `SCREENSHOT_TESTS_FILE`（改行区切りファイル、主）/ `SCREENSHOT_TESTS`（カンマ区切り、補助）の読込。
- 両方指定された場合の和集合処理。
- パス正規化（`./` 付き・絶対パス・末尾改行などのゆらぎを吸収して比較可能にする）。正規化は対象リスト側・`context.test_file` 側の両方に同じ規則を適用する。
- Env AND TargetList のデフォルトポリシー合成の実装。P3 で先出しした「`configure` 未使用時のデフォルト」契約をここで確定する。

### 含まないもの（Non-goals）

- `Capybara::Storyboard.configure` / `Configuration` オブジェクトそのものの実装（P5 の関心事。ただし P5 が完成した後にデフォルトポリシーが上書きされる余地は本フェーズの設計で確保しておく）。
- 変更ファイル → 対象テストのマッピング（TIA・規約マッピング）。gem 外の関心事（overview.md §1.3・§12）。
- README・docs 本文（有効化モデルの説明・CI 連携レシピ）。P6・P7 で扱う。

## 3. 前提・依存

- 先行フェーズ: P3（ポリシー抽象 + EnvPolicy）完了が前提。ポリシー契約（`call(context) -> Boolean`）と `Context` が実装済みであること。
- 並行可能フェーズ: P5（Configuration）とは P3 完了後に並行して進行可能（本フェーズは `policy=` 経由の差し替え口を変更しないため、P5 の `Configuration` 実装と衝突しにくい）。ただし両フェーズが同じ「デフォルトポリシー構築処理」に触れる場合は、統合時にコンフリクト解消が必要になる可能性がある点に注意する。
- 外部前提: なし。

## 4. 実装方針

- `lib/capybara/storyboard/policies/target_list_policy.rb` に `TargetListPolicy` を置く。責務は「正規化済みパス集合と `context.test_file` の包含判定」のみとし、ENV の読込・パスの生データ取得は行わない（ポリシー自体はピュアな集合演算に徹する）。
- ENV からの読込（`SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS` の読込・和集合化・正規化）は `TargetListPolicy` の外側、デフォルトポリシー構築箇所（`Capybara::Storyboard` モジュール、または専用のファクトリメソッド）に置く。これにより `TargetListPolicy` 自体は「ENV を知らないピュアなポリシー」として単体テストしやすくする。
- パス正規化ロジックは一箇所（例: モジュール内のプライベートユーティリティメソッドか、`TargetListPolicy` 生成時の前処理）に集約し、対象リスト側・`context.test_file` 側の双方から呼ばれる形にして、正規化規則のズレを防ぐ。
- 合成ポリシー（Env AND TargetList）の実装形式（明示クラスにするか、`policy=` に渡す proc/合成オブジェクトにするか）を本フェーズで確定する。デフォルトポリシー構築箇所で `EnvPolicy` と `TargetListPolicy` の両方の評価結果を AND 結合する薄いラッパーとして実装し、`policy=` で利用者が独自ポリシーに置き換えられる余地を保つ。
- デフォルトポリシーは「`SCREENSHOT_TESTS_FILE`/`SCREENSHOT_TESTS` を読み込んで `TargetListPolicy` を構築し、`EnvPolicy` と AND 合成したもの」として、`Capybara::Storyboard` モジュールの初期化時（もしくは初回アクセス時の遅延構築）に組み立てる。

## 5. 変更ファイル

- 新規: `lib/capybara/storyboard/policies/target_list_policy.rb`
- 変更: デフォルトポリシー構築箇所（`lib/capybara/storyboard.rb`、または P3 で用意したデフォルト構築メソッドの実体があるファイル）
- テスト（RSpec）:
  - 新規: `spec/capybara/storyboard/policies/target_list_policy_spec.rb`
  - 変更: デフォルトポリシー合成を検証するテスト（`spec/capybara/storyboard_spec.rb` 等、合成ポリシーの結合テストを追加する箇所）
- ドキュメント: なし（本フェーズでは README・docs 本文には触れない。仕様の README 明記は P6 で行う）。

## 6. 受け入れ条件

- [ ] overview.md §5 の3ケースを再現する:
  - 無効（`SCREENSHOTS` 未設定）→ 撮影なし。
  - 全撮影（`SCREENSHOTS=1`、対象リスト未指定）→ 全 system test で撮影。
  - 選択撮影（`SCREENSHOTS=1` + `SCREENSHOT_TESTS_FILE`/`SCREENSHOT_TESTS` 指定）→ 指定ファイルのみ撮影。
- [ ] パス正規化のゆらぎ（`./` 付き、絶対パス、末尾改行）を吸収して比較できることを検証する。
- [ ] `SCREENSHOT_TESTS_FILE` と `SCREENSHOT_TESTS` を両方指定した場合に和集合として扱われる。
- [ ] 対象リストが空集合の場合は「絞り込みなし」= 全撮影という後方互換が保たれる。
- [ ] `TargetListPolicy` 単体テストが緑（ENV に依存しないピュアな集合判定であることを含む）。
- [ ] CI（spec + sgcop/rubocop）が緑。

## 7. テスト観点

- **単体**: `TargetListPolicy#call` を `Context` フィクスチャと様々な集合（空集合・単一要素・複数要素）で検証する。ENV や Capybara には一切依存しない形でテストする。
- **単体**: パス正規化ロジックを単体で検証する。`./spec/system/foo_spec.rb`・`/abs/path/spec/system/foo_spec.rb`・末尾改行付き文字列などのバリエーションを網羅する。
- **結合**: `SCREENSHOT_TESTS_FILE`・`SCREENSHOT_TESTS` の読込から正規化・和集合・`TargetListPolicy` 構築までを結合的に検証する。両方指定・片方のみ指定・両方未指定のケースを網羅する。
- **結合**: デフォルトポリシー（Env AND TargetList）が、overview.md §5 の3ケースそれぞれで正しい真偽を返すことを検証する。
- **エッジケース**:
  - `SCREENSHOT_TESTS_FILE` が指し示すファイルが空ファイルの場合（対象なし = 撮影 0 件、後方互換の「絞り込みなし」とは異なる状態であることに注意。空ファイル指定は「空集合」ではなく「対象ファイルが0件と明示された」ケースであり、overview.md §6 の「対象なし（空ファイル）の場合の挙動 = 撮影0件」に従うことを確認する）。
  - `SCREENSHOT_TESTS_FILE` 自体が未指定・`SCREENSHOT_TESTS` のみ指定など、片方のみのケース。
  - 存在しないファイルパスが `SCREENSHOT_TESTS_FILE` に指定された場合の扱い（エラーにするか無視するかを決めてテストに反映する）。

## 8. リスク・決定事項

このフェーズで確定させる overview.md §11 の決定事項:

- **合成ポリシーを明示クラスにするか、`policy=` に合成オブジェクト/proc を渡す形にするか**: 本フェーズで実装しながら確定する（P3 で契約のみ先出し済み）。
- **`SCREENSHOT_TESTS_FILE` と `SCREENSHOT_TESTS` 併用時の統合仕様（和集合）**: 本フェーズで最終確認・実装する（README への明記は P6）。

リスク:

- 空ファイル指定（対象ファイル0件が明示されたケース）と、そもそも `SCREENSHOT_TESTS_FILE`/`SCREENSHOT_TESTS` が未指定のケース（対象リストが空集合＝絞り込みなし）を混同すると、overview.md §6 の意図（空ファイル=撮影0件）と後方互換要件（未指定=全撮影）が矛盾する実装になりうる。両者を明確に区別するテストケースを用意して防ぐ。
- パス正規化の規則が `TargetListPolicy` 側と ENV 読込側でズレると、集合比較が一致せず「対象に含まれているのに撮影されない」不具合につながる。正規化ロジックを一箇所に集約する実装方針（§4）で対応する。

## 9. 参照

- overview.md §3.4（ポリシー抽象、`TargetListPolicy` と合成ポリシー）
- overview.md §3.7（対象集合の渡し方）
- overview.md §5（有効化モデルのまとめ）
- overview.md §6（GitHub Actions 連携、空ファイル時の挙動の注意点）
- 既存ファイル: `lib/capybara/storyboard/policies/env_policy.rb`（P3 で作成）、`lib/capybara/storyboard/context.rb`（P3 で作成）
