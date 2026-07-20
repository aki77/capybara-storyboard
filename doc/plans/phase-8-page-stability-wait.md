# Phase 8: ページ安定待機

## 1. 目的

overview.md §3.6 が必須仕様として定義する「撮影直前のページ安定待機」機構（`document.getAnimations()` が返す実行中アニメーションが 0 件、かつ `MutationObserver` で監視した DOM の最終変更からの経過時間がチェック間隔以上、の両方をポーリングで待つ）を実装する。P2 で実装したアクション instrumentation の撮影直前フックにこの待機を挟み、アニメーション途中や DOM 変更直後の不安定な画面を撮影してしまうことを防ぐ。対応する仕様は overview.md §3.6（アクション instrumentation・ページ安定待機）。

## 2. スコープ

### 含むもの

- ページ安定待機機構本体の実装（`document.getAnimations()` チェック + `MutationObserver` によるポーリング）。
- ポーリング間隔・最大試行回数の決定と実装。
- 除外アニメーション名リスト（チェック対象から無視するアニメーション名）の決定と実装。
- タイムアウト時挙動（最大試行回数に達しても安定しない場合に、テストを失敗させるかログ出力のみに留めるか）の決定と実装。
- `MutationObserver` の撮影ごとの setup / teardown（状態をグローバルに残さない）。
- 撮影可否の判定（ポリシー）が false のときは、この待機処理自体を一切実行しない（overview.md 設計原則3のゼロオーバーヘッドを維持）。

### 含まないもの（Non-goals）

- P2 で実装済みのアクション instrumentation 本体（撮影フックの登録・前後撮影の振り分け）の変更。本フェーズは既存の撮影直前フックに待機呼び出しを追加するのみで、フック自体の構造は変えない。
- `Capybara::Storyboard.configure` によるパラメータ上書き API の実装。パラメータの決定・実装は本フェーズで行うが、利用者向けの設定スキーマへの反映は P5（Configuration）のスコープとする。本フェーズはデフォルト値での実装完了までを担う。
- ポリシー抽象・対象リストなど、撮影可否判定そのものに関わる変更（P3/P4 で確定済み）。

## 3. 前提・依存

- **先行フェーズ**: P2（コア移植）完了が前提。アクション instrumentation の撮影直前フックが 1 箇所に集約されていること（`Session#auto` / `Session#capture` などの呼び出し口）。
- **並行可能フェーズ**: なし。パラメータの `configure` 上書きは P5 と協調が必要なため、P5 側の設定スキーマ確定は本フェーズの実装内容（パラメータの名前・型・デフォルト値）が固まった後に反映する。
- **外部前提**: Capybara の `page.evaluate_script` / `page.execute_script`（または同等の JS 実行手段）が利用可能なこと。ブラウザドライバが `document.getAnimations()` および `MutationObserver` をサポートすること（Rack::Test 等の非 JS ドライバでは本機構は事実上no-opになり得る点は受け入れ条件・テスト観点で扱う）。

## 4. 実装方針

- 撮影直前フック（P2 で実装した `Session` の撮影呼び出し口、例: `Session#auto` / `Session#capture` の内部）に、安定待機の呼び出しを 1 箇所挟む。待機ロジック自体は撮影呼び出し口とは別クラス/モジュールに切り出し、責務を分離する。
- 安定待機ロジックは新規クラス（例: `Capybara::Storyboard::PageStability`）に置き、`wait!(page)` のような単一の呼び出し口を持たせる。責務は「与えられた `page` に対してポーリングし、安定を確認する（またはタイムアウトを処理する）」ことのみとする。
- JS 実行は `page.evaluate_script` / `page.execute_script` を用い、`document.getAnimations()` の件数取得と `MutationObserver` の setup/teardown を行う。`MutationObserver` は撮影のたびに新規 setup し、撮影後（または待機完了後）に teardown してグローバル状態を残さない。
- ポーリング間隔・最大試行回数はデフォルト値を本フェーズで決定し実装する。除外アニメーション名リストも同様にデフォルト値（空リストまたは既知の無限ループ系アニメーション名）を決定する。
- タイムアウト時挙動は、テストを失敗させる（例外送出）かログ出力のみに留めるかを本フェーズで決定する。撮影機構自体の信頼性を優先し、待機に失敗してもスクリーンショット撮影自体は継続できるようにする方向で検討する（決定内容は §8 に記録）。
- ポリシーが false（機構自体が無効）のときは、`Session` 側で待機呼び出しそのものをスキップする分岐を設け、待機ロジックの呼び出しコストがゼロになるようにする。

## 5. 変更ファイル

実装完了時点の実際の変更ファイル一覧（当初計画から、設定アクセサ追加および手動撮影の意味論変更に伴い変更範囲が広がった）:

- 新規: `lib/capybara/storyboard/page_stability.rb`（安定待機ロジック本体。`wait_for_stable_page` / `setup` / `check` / `cleanup` / `stable?` / `warn_unstable` / `non_js_driver_error?` を module_function として実装）
- 変更: `lib/capybara/storyboard/session.rb`（`capture_with_label` 内の `save_screenshot` 直前に `wait_for_stable_page` 呼び出しを追加。加えて手動撮影の意味論変更に伴い `Session#capture`（常時撮影）を `Session#manual`（enabled ガード付き、`#auto` と同じ経路）にリネーム）
- 変更: `lib/capybara/storyboard/configuration.rb`（`page_stability_interval` / `page_stability_max_attempts` / `page_stability_excluded_animations` の 3 アクセサを追加。既存 `output_dir` / `policy` と同じ遅延デフォルトパターン。デフォルト値は `DEFAULT_PAGE_STABILITY_INTERVAL` などの定数として定義）
- 変更: `lib/capybara/storyboard.rb`（`page_stability.rb` の require 追加）
- 変更: `lib/capybara/storyboard/test_helper.rb`（**当初計画になかった変更**。手動撮影 DSL メソッド名 `screenshot(label)` を `storyboard_screenshot(label)` に改名し、実装を `@__storyboard.capture(...)` から `@__storyboard.manual(...)` 呼び出しに変更）
- テスト（RSpec）:
  - 新規: `spec/capybara/storyboard/page_stability_spec.rb`（フェイクページ/フェイク JS 実行ハーネスによる単体テスト）
  - 変更: `spec/capybara/storyboard/session_spec.rb`（撮影直前に待機が呼ばれること・無効時に呼ばれないこと・`manual` メソッドの enabled ガードの確認を追加）
  - 変更: `spec/capybara/storyboard/test_helper_spec.rb`（`storyboard_screenshot(label)` がポリシー無効時に撮影しないことの確認に更新。フェイクページに `execute_script` / `evaluate_script` のスタブを追加）
- ドキュメント: なし（利用者向け設定ドキュメントへの反映は P5/P6 の責務）。

## 6. 受け入れ条件

- [x] 撮影直前に安定待機が実行されること（撮影フックからの呼び出しが確認できる）。`Session#capture_with_label` 内で `save_screenshot` 直前に `wait_for_stable_page` を呼び出す形で実装。
- [x] `document.getAnimations()` が実行中アニメーションを返す間は待機し続け、0 件になってから撮影されること（除外リストに含まれるアニメーション名は無視されること）。
- [x] `MutationObserver` で DOM の最終変更からの経過時間がチェック間隔未満の間は待機し続けること。
- [x] 最大試行回数に達した場合のタイムアウト時挙動が、決定した仕様どおりに動作すること（warn ログ出力のみ・撮影継続。§8 参照）。
- [x] 撮影可否判定（ポリシー）が false のとき、安定待機処理自体が一切実行されないこと（ゼロオーバーヘッドの確認）。`auto`/`manual` の呼び出し口が enabled ガード済みのため、`capture_with_label` 自体に到達しない。
- [x] `MutationObserver` が撮影のたびに setup/teardown され、グローバルな状態が残らないこと（`cleanup` は `ensure` 節で実行され、setup 未実施・非 JS ドライバでも例外を漏らさない）。
- [x] CI（spec + sgcop/rubocop）が緑。spec 106 examples 0 failures、rubocop 22 files inspected 0 offenses で確認済み。

## 7. テスト観点

- **単体**: `PageStability` にフェイクの JS 実行結果（アニメーション件数・DOM 変更経過時間を差し替え可能なスタブ）を与え、ポーリングの継続・終了条件・タイムアウト挙動を検証する。実ブラウザは使わない。
- **結合**: `Session` の撮影直前フックから `PageStability` が呼ばれること、ポリシー無効時に呼ばれないことをスタブ（呼び出し回数カウント）で検証する。
- **エッジケース**:
  - 除外アニメーション名リストに該当するアニメーションのみが実行中の場合、待機がブロックされずに進むこと。
  - `getAnimations()` や `MutationObserver` が利用できないドライバ（非 JS ドライバ等）での挙動（no-op として安全にスキップされるか、明示的にエラーになるかを決定し、その通りに振る舞うこと）。
  - ポーリング間隔・最大試行回数の境界値（0 回・上限到達直前）での挙動。
  - タイムアウト時にテストを失敗させる設定の場合、例外がテスト側に伝播すること。ログのみに留める設定の場合、撮影処理自体は継続されること。

## 8. リスク・決定事項

このフェーズで確定した overview.md §11 の決定事項（実装完了・確定値）:

- **ポーリング間隔**: デフォルト **0.5 秒**。設定名 `page_stability_interval`（`Configuration#page_stability_interval` / `=`、`Capybara::Storyboard.configure` から上書き可能）。
- **最大試行回数**: デフォルト **10 回**。設定名 `page_stability_max_attempts`。
- **除外アニメーション名リスト**: デフォルト **空リスト `[]`**。設定名 `page_stability_excluded_animations`。既知の無限ループ系アニメーション名を初期値として持たせる案は採用せず、明示的な opt-in（利用者が `configure` で指定）とした。
- **タイムアウト時挙動**: **warn ログ（STDERR）出力のみに留め、撮影は継続する（例外は投げない）と確定**。opt-in の例外送出オプションも設けない。**踏襲元の gist（capybara_screenshot_helper.rb）にある `raise` は不採用**。理由: 撮影機構自体の信頼性を優先し、安定待機の失敗によって既存 system spec が不安定化（flaky 化）するリスクを避けるため。
- **非 JS ドライバでの挙動**: `Capybara::NotSupportedByDriverError` / `Selenium::WebDriver::Error::JavascriptError` を rescue し、no-op で安全にスキップすると確定。両定数とも `defined?` で存在確認してから rescue 対象に加えるため、Capybara/Selenium がロードされていないテスト環境でも例外を漏らさない。
- **踏襲元 JS からの意図的な差分（コードレビュー指摘による後追い決定）**: `document.getAnimations()` のフィルタに `animation.playState === 'running'` のチェックを追加した（踏襲元の `capybara_screenshot_helper.rb` にはこの判定がない）。理由: `getAnimations()` は finished/paused のアニメーションも、cancel されるか要素が DOM から除去されるまで結果に残り続けるため、`playState` を見ずに件数だけで判定すると完了済みアニメーションを永久に「実行中」と誤判定し、安定待機が毎回タイムアウトして無駄な待機と warning ログを発生させてしまう。コードレビューでの指摘を受け、ユーザー承認のもと原典からの意図的な逸脱として採用した。overview.md §3.6 にも SSOT としてこの差分を明記済み。
- **手動スクショの意味論変更（レビュー指摘 c_a67826 による後追い決定）**: 当初 `Session#capture` は SCREENSHOTS ゲート（ポリシー）と無関係に常時撮影する仕様だったが、本フェーズで **`Session#manual`** にリネームし、**ポリシーが有効なとき（`#auto` と同じゲート）のみ撮影する** 意味論に改訂した。単なる無条件スクショが必要な場合は Capybara 標準の `save_screenshot` を使う想定。**あわせて DSL 側のメソッド名も `screenshot(label)` から `storyboard_screenshot(label)` に改名した**（`lib/capybara/storyboard/test_helper.rb` の `def screenshot(label)` を `def storyboard_screenshot(label)` に変更。内部実装も `@__storyboard.capture` → `@__storyboard.manual` に変更）。
- **rescue 範囲の再拡大（コードレビュー指摘による後追い決定）**: 上記「非 JS ドライバでの挙動」の限定 rescue（`Capybara::NotSupportedByDriverError` / `Selenium::WebDriver::Error::JavascriptError` のみ）は、コードレビューで「gem は特定ドライバに依存せず、利用者が Cuprite(Ferrum) 等 Selenium 以外の JS ドライバを使う可能性が高い。この限定 rescue では Cuprite の `Ferrum::JavaScriptError` 等、想定していないドライバ例外が発生した場合に安定待機の失敗がそのままスクリーンショット撮影自体を巻き込んで落としてしまう」と指摘され、ユーザー承認のうえ `wait_for_stable_page` の rescue 節を `rescue StandardError => e` に変更した。あわせて例外の扱いを二段階にした:
  - `non_js_driver_error?(e)` が true（`Capybara::NotSupportedByDriverError` / `Selenium::WebDriver::Error::JavascriptError` のいずれか。定数は `defined?` ガードで判定）の「JS 非対応の想定内エラー」は、従来どおり**静かにスキップ**（warn なし）。
  - それ以外の予期しない `StandardError`（Cuprite/Ferrum の `Ferrum::JavaScriptError` 等を含む）は、`warn("capybara-storyboard: page stability wait skipped after error: ...")` で STDERR に出力してから no-op とする。撮影自体は必ず継続され、ドライバ異常だけが可視化される。
  - 根拠: 本 gem はどの Capybara ドライバ（Selenium / Cuprite / Rack::Test 等）にも依存しないため、rescue 対象をドライバ固有の例外クラスに限定すると未知のドライバで安定待機が撮影を巻き込んで失敗させてしまう。「待機の失敗は撮影を妨げない」という不変条件をドライバ非依存に保証するため、rescue 範囲を `StandardError` 全体に広げた。

overview.md §11 の当該項目は上記の確定値・命名で「確定済み」に更新済み（§3.6 の未確定文言も同様に更新済み）。

リスク（解消済み）:

- ブラウザドライバ（Selenium/Cuprite 等）ごとの `document.getAnimations()` 対応状況の差異 → 非 JS ドライバは `defined?` ガード付きの rescue で吸収し、対応済みドライバでは通常どおり動作する形で決定・実装済み。
- タイムアウト時にテストを失敗させる設計だった場合の flaky 化リスク → warn ログのみ・撮影継続に確定したことで解消。
- P5（Configuration）との協調 → `page_stability_interval` / `page_stability_max_attempts` / `page_stability_excluded_animations` の 3 アクセサとして `Configuration` に実装済み。命名・型の齟齬は生じていない。

## 9. 参照

- overview.md §3.6（アクション instrumentation・ページ安定待機の仕様本文、SSOT）
- overview.md §11（実装時に確定させる決定事項。本フェーズで安定待機パラメータを確定）
- [phase-2-core-port.md](phase-2-core-port.md)（P2: アクション instrumentation・撮影直前フックの実装内容。本フェーズが待機呼び出しを挟む対象）
- [phase-5-configuration.md](phase-5-configuration.md)（P5: 本フェーズで確定したパラメータの `configure` 経由での上書きに反映）
- SonicGarden/wlb-morning-mail の [capybara_screenshot_helper.rb](https://github.com/SonicGarden/wlb-morning-mail/blob/release-candidate/spec/support/helpers/capybara_screenshot_helper.rb)（overview.md §3.6 が踏襲元として参照する実装）
