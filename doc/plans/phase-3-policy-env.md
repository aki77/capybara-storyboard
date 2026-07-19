# Phase 3: ポリシー抽象 + EnvPolicy

## 1. 目的

P2 で単一ブールとして実装した撮影可否判定を、差し替え可能なポリシーオブジェクト（`call(context) -> Boolean`）経由の判定に置き換える。これにより P4 の対象リストポリシー・P5 の Configuration がリグレッションなく積み上げられる土台を作る。対応する仕様は overview.md §2 の設計原則1（決定的処理とポリシー判定の分離）、§3.3（判定コンテキスト）、§3.4（ポリシー抽象）。

## 2. スコープ

### 含むもの

- `Capybara::Storyboard::Context` 値オブジェクトの新規導入。フィールドは `test_class_name` / `test_method_name` / `test_file`（overview.md §3.3）。
- ポリシーの抽象契約（`call(context) -> Boolean` に応答するオブジェクト）の確立。
- `Capybara::Storyboard::Policies::EnvPolicy` の新規実装。`ENV["SCREENSHOTS"].present?` を返す、従来動作（機構全体の arm）を担う。
- `TestHelper` 側の判定ロジックを、P2 で実装したプライベート判定メソッドからポリシーオブジェクト呼び出しに差し替える。
- per-test で一度だけポリシーを評価し、結果をキャッシュする仕組み（ホットパスでの再評価を避ける）。
- デフォルトポリシーの位置づけの先出し: 「`configure` 未使用時のデフォルト = P4 で確定するデフォルトポリシー（Env AND TargetList）と同一のインターフェースに従う」という契約を、本フェーズの受け入れ条件に含めておく。これにより P4・P5 の並行実装を安全にする。

### 含まないもの（Non-goals）

- `TargetListPolicy` の実装。P4 で行う。
- Env AND TargetList の合成ポリシーの実装。P4 で行う。
- `Capybara::Storyboard.configure` / `Configuration` オブジェクトの実装。P5 で行う。
- 対象リスト（`SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS`）読込。P4 で行う。

## 3. 前提・依存

- 先行フェーズ: P2（コア移植）完了が前提。`TestHelper` の判定呼び出し口が 1 箇所に集約されていること。
- 並行可能フェーズ: なし（P4・P5 はいずれも本フェーズの完了を前提にする）。
- 外部前提: なし（P2 までの前提を引き継ぐ）。

## 4. 実装方針

- `lib/capybara/storyboard/context.rb` に `Context` を置く。責務は「テスト単位の識別情報を保持する値オブジェクト」のみとし、生成ロジック（RSpec example メタデータからの導出）は `TestHelper` 側（P2 で実装済みのパス導出ロジック）に残し、`Context` 自体は受け取った値を保持するだけの薄い責務にする。
- `lib/capybara/storyboard/policies/env_policy.rb` に `EnvPolicy` を置く。責務は「`ENV["SCREENSHOTS"]` を読んで真偽を返す」ことのみとし、`Context` の内容には一切依存しない（`call(context)` は引数を受け取るがロジックには使わない）ことを明記する。
- `Capybara::Storyboard.policy` / `.policy=` のアクセサをトップレベルモジュールに置き、未設定時はデフォルトポリシー（本フェーズ時点では `EnvPolicy` のインスタンス）を返す。デフォルトポリシーの構築処理は、P4 で TargetList を合成できるよう 1 箇所（例: モジュールのプライベートなデフォルト構築メソッド）に閉じ込めておく。
- `TestHelper` は per-test の setup（`before` フック）で `Context` を 1 度だけ生成し、同時に `Capybara::Storyboard.policy.call(context)` を 1 度だけ評価してインスタンス変数にキャッシュする。以降のアクションフックはこのキャッシュ済み真偽値のみを参照し、ポリシー呼び出しやフック内での再評価は行わない。
- ポリシーオブジェクトの契約（`call(context) -> Boolean`）はコードコメントやテストで明文化し、P4 の `TargetListPolicy` や将来の利用者独自ポリシーが同じ契約に従えるようにする。

## 5. 変更ファイル

- 新規: `lib/capybara/storyboard/context.rb`
- 新規: `lib/capybara/storyboard/policies/env_policy.rb`
- 変更: `lib/capybara/storyboard/test_helper.rb`（判定をポリシー経由の呼び出しに差し替え、per-test キャッシュの導入）
- 変更: `lib/capybara/storyboard.rb`（`require` 追加、`policy` / `policy=` アクセサの追加）
- テスト（RSpec）:
  - 新規: `spec/capybara/storyboard/context_spec.rb`
  - 新規: `spec/capybara/storyboard/policies/env_policy_spec.rb`
  - 変更: `spec/capybara/storyboard/test_helper_spec.rb`（ポリシー経由判定への差し替えに伴う調整。挙動そのものは P2 と一致させる）
- ドキュメント: なし。

## 6. 受け入れ条件

- [ ] P2 で実装した挙動（前後撮影・手動 screenshot・ファイル名・出力先）と完全に一致する（リグレッションなし）。
- [ ] `EnvPolicy` 単体テストが緑（`ENV["SCREENSHOTS"]` の有無で真偽が切り替わることを検証）。
- [ ] `Context` が `test_class_name` / `test_method_name` / `test_file` を保持できる。
- [ ] ポリシーの評価が per-test で 1 回のみであること（同一テスト内で複数アクションを実行しても再評価されないこと）が確認できる。
- [ ] `Capybara::Storyboard.policy` / `.policy=` が読み書きでき、未設定時にデフォルトポリシーが使われる。
- [ ] 「`configure` 未使用時のデフォルト = P4 のデフォルトポリシーと同一インターフェース」の契約が明文化され、P4/P5 の並行実装者が参照できる。
- [ ] CI（spec + sgcop/rubocop）が緑。

## 7. テスト観点

- **単体**: `EnvPolicy#call` が `Context` フィクスチャを渡されたときに ENV の状態のみで真偽を返すこと（`Context` の内容を無視すること）を検証する。
- **単体**: `Context` の値保持（生成時に渡した値がそのまま読めること）を検証する。
- **結合**: `TestHelper` がポリシー経由で判定した結果をキャッシュし、per-test で 1 回しかポリシーを呼び出さないことをスタブ（呼び出し回数カウント）で検証する。
- **エッジケース**:
  - `ENV["SCREENSHOTS"]` が空文字列・`"0"` など「設定されているが偽と解釈すべき値」の場合の挙動（`present?` の意味論に従うことを明記）。
  - `policy=` でカスタムポリシー（テスト用のダミーオブジェクト）を注入した場合に、`TestHelper` がそれを正しく利用すること。
  - テスト実行途中でポリシーを差し替えても、同一テスト内でキャッシュ済みの評価結果には影響しない（次のテストから反映される）ことの確認。

## 8. リスク・決定事項

このフェーズで確定させる overview.md §11 の決定事項:

- なし（本フェーズは P4 で確定する「合成ポリシーの形」の **枠組みの先出し** に留める。実際の合成ポリシーの実装形式・確定はP4で行う）。

リスク:

- ポリシー経由への差し替えで P2 の挙動に微妙な差異（キャッシュタイミングのズレ等）が生じるリスクがある。受け入れ条件で「P2 との完全一致」を明記し、既存の `test_helper_spec.rb` をそのまま再利用して回帰確認することでリスクを低減する。
- `Context` の責務を薄くしすぎると、P4 でのパス正規化ロジックの置き場所に迷いが生じる可能性がある。パス正規化は `Context` 生成前（`TestHelper` 側）で完結させる方針をここで明確にしておく。

## 9. 参照

- overview.md §2（設計原則、特に1: 決定的処理とポリシー判定の分離）
- overview.md §3.3（判定コンテキスト）、§3.4（ポリシー抽象）
- 既存ファイル: `lib/capybara/storyboard/test_helper.rb`（P2 で作成）
