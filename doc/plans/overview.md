# capybara-storyboard 設計仕様（Overview / SSOT）

> このドキュメントは capybara-storyboard の **フェーズ非依存な設計仕様の単一参照元（single source of truth）** である。
> 実際の Ruby 実装コードは含めない。
> 実装は「1 フェーズ = 1 PR」を原則としてフェーズ単位で進める。フェーズ分割・各フェーズの実装計画は [README.md](README.md)（索引）と各 `phase-N-*.md` を参照。
> このドキュメントは「何を作るか（仕様）」を、各フェーズドキュメントは「どの順でどう作るか（計画）」を担う。

---

## 1. 目的とスコープ

### 1.1 目的

システムテスト（Capybara）の実行中に、各アクションの前後スクリーンショットを **連番・テスト単位のディレクトリ構成** で自動記録する仕組みを gem 化する。用途は 2 つ:

1. **人間による視覚的検証** — UI 変更・レイアウト崩れ・複数ステップフローの確認。
2. **AI エージェント（Claude Code 等）による検証** — 変更に関係する画面の順序付き集合をエージェントに読ませて UI の妥当性を検証させる。

元になっているのは gist の `AutoScreenshots` concern（ENV `SCREENSHOTS` による ON/OFF 切替のみ）。本 gem ではこれを拡張し、**「どのテストで撮るか」をポリシーで制御可能** にする。特に GitHub Actions 上で「PR 内で変更のあったシステムテストファイルのみ有効化」するユースケースを一級市民として扱う。

### 1.2 スコープに含むもの

- Capybara アクションのオーバーライドによる自動スクショ（元 concern の移植）。
- 手動 `storyboard_screenshot(label)` API（撮影可否判定ポリシーが有効なときに撮影。Phase 8 で確定。詳細は§3.2）。
- 撮影可否をテスト単位で判定する **ポリシー抽象**。
- ポリシー実装: ENV ベース（後方互換）と **テストファイルパス指定ベース**。
- 対象集合の受け取り口（ENV 経由でファイルパスのリストを渡す）。
- GitHub Actions 連携レシピ（diff → 対象テストファイル抽出 → gem に渡す）。
- README・エージェント向けワークフロー文書。

### 1.3 スコープに含まないもの（明示的に非対象）

- **実行対象テストの絞り込み（test selection）**。gem は「どのテストで撮るか」だけを担う。実行速度目的のテスト選択は別関心事とし、gem は関与しない（同じ対象リストを両方で使い回すのは利用者側の自由）。
- **変更ファイル → 対象テストのマッピング（TIA / カバレッジ / 規約マッピング）**。対象集合の作り方は gem 外の関心事。gem は「テストファイルパスのリストを受け取って判定する」ところまで。
- 失敗時のみ撮影する機能（既存 `capybara-screenshot` の領分。本 gem は撮影対象を明示制御する方向で差別化）。
- スクショの diff・画像比較（visual regression）。将来検討（§12）。

---

## 2. 設計原則

1. **決定的処理とポリシー判定の分離**: 「撮る仕組み（アクション instrumentation）」と「撮るか否かの判定（ポリシー）」を分ける。ポリシーは差し替え可能なオブジェクトとして扱う。
2. **後方互換の維持**: 既存 gist 利用者が `SCREENSHOTS=1` だけで従来どおり「全テスト撮影」できること。対象リスト未指定時の挙動は現状と一致させる。
3. **ゼロオーバーヘッド（無効時）**: `SCREENSHOTS` 未設定時はアクションフックが一切走らないこと。判定は per-test 一度だけ評価し、フックのホットパスで重い処理をしない。
4. **gem は集合を受け取るだけ**: 対象テスト集合の生成ロジック（git diff 等）は gem に持ち込まない。渡し口だけを提供する。
5. **成果物はエージェント可読な構造**: 出力ディレクトリは「テストごと・連番・アクション名入りファイル名」を維持し、そのままエージェント入力として使える形にする。

---

## 3. アーキテクチャ

### 3.1 名前空間

- トップレベル: `Capybara::Storyboard`
- テスト側で include するモジュール: `Capybara::Storyboard::TestHelper`（元 `AutoScreenshots` concern に相当）

### 3.2 公開 API（インターフェース仕様。実装ではない）

以下はシグネチャと振る舞いの仕様。実装フェーズで具体化する。

- `Capybara::Storyboard.configure { |config| ... }`
  - 設定オブジェクトを yield。出力ディレクトリ・ポリシーの上書きなどを設定できる。
- `Capybara::Storyboard.policy` / `.policy=`
  - 現在有効なポリシーオブジェクト。未設定時はデフォルトポリシー（§3.4）。
- `Capybara::Storyboard::TestHelper`（include 用モジュール）
  - `included` フックで setup を登録し、per-test の初期化を行う。
  - `storyboard_screenshot(label)` — 手動撮影フック。**Phase 8 で意味論を改訂**: 「ENV に関係なく常に撮影」ではなく、**ポリシーが有効なとき（auto と同じゲート）のみ撮影する**。単なる無条件スクショが必要な場合は Capybara 標準の `save_screenshot` を使う想定。連番カウンタと出力ディレクトリを自動撮影と共有する。**あわせて DSL メソッド名も `screenshot` から `storyboard_screenshot` に改名した（Phase 8）**。
  - 各 Capybara アクションのオーバーライド（§3.6）。

### 3.3 判定コンテキスト

ポリシーに渡す値オブジェクト。テスト単位で 1 度だけ生成する。

- `Capybara::Storyboard::Context`
  - フィールド: `test_class_name`（例: `ParticipationsSystemTest` 相当のグルーピング識別子）、`test_method_name`（例: 個々の example 名）、`test_file`（**RSpec の生の file_path 文字列。`Context` 自身は正規化しない**。Rails.root 相対への正規化は比較時にオンデマンドで行う。§3.4/§3.5 参照）。
  - `test_file` は **RSpec の example メタデータ（`example.metadata[:file_path]` 等）** から導出する（§3.5）。

### 3.4 ポリシー抽象

ポリシーは `call(context) -> Boolean` に応答するオブジェクト。

実装するポリシー:

- `EnvPolicy`
  - `ENV["SCREENSHOTS"].present?` を返す。従来動作（機構全体の arm）。
- `TargetListPolicy`
  - コンストラクタで対象テストファイルパスの集合（正規化済み）を受け取る。
  - `context.test_file` が集合に含まれれば `true`。
  - **`TargetListPolicy` 単体の契約は「集合が空なら常に `false`（対象0件）」**（Phase 4 で確定。旧仕様の「空集合なら絞り込みなし=true」から改訂）。空集合の `TargetListPolicy` が存在するということ自体が「明示的に対象0件」を意味する。
  - 後方互換の「対象リスト未指定＝全撮影」は `TargetListPolicy` 自身の責務ではなく、**対象リストが未指定のときは合成側（default_policy）がそもそも `TargetListPolicy` を構築しない**ことで担保する（下記デフォルトポリシー参照）。
- 合成ポリシー（AND）
  - 「機構が arm されている（Env）」かつ「対象に含まれる（TargetList）」を満たすときのみ撮影、という合成を表現する。
  - **実装形式は薄い lambda に確定**（`->(context) { env.call(context) && target.call(context) }`）。proc は `#call` に応答し `call(context) -> Boolean` の契約を満たすため、明示クラスは採用しなかった。`policy=` による差し替え口はこの合成後のオブジェクトごと上書きできる。

**デフォルトポリシー**（`configure` で上書きされない場合）。SCREENSHOT_TESTS_FILE / SCREENSHOT_TESTS のどちらも未指定かどうかで分岐する:

```
SCREENSHOT_TESTS_FILE も SCREENSHOT_TESTS も未指定
  => EnvPolicy 単体（TargetListPolicy は構築しない）＝ 後方互換の全撮影

どちらか一方でも明示指定あり（空ファイル指定を含む）
  => EnvPolicy AND TargetListPolicy（対象集合が空なら常に false ＝ 撮影0件）
```

ENV からの対象リスト読み込み（§3.7）はデフォルトポリシー構築時に行う。正規化は §3.5 で述べる `normalize_test_path` に一本化し、対象リスト側・`context.test_file` 側の双方がこの同じ関数を通る。

### 3.5 テストファイルパスの導出

- **RSpec の system spec を前提とする。** 撮影対象の判定に用いる `context.test_file` は、RSpec の example メタデータ（`example.metadata[:file_path]` 等）から取得する。クラス名からの規約変換ではなく、実行中の spec ファイルパスを直接利用できるため確実。
- `Context#test_file` は生の file_path を保持したままにし、比較の直前に Rails.root 相対（Rails 未定義時は `Dir.pwd` 相対）へオンデマンドで正規化する。正規化は `Capybara::Storyboard.normalize_test_path` という 1 つの関数に集約し、対象リスト側（`default_policy` で集合を組むとき）・`context.test_file` 側（`TargetListPolicy#call` で比較するとき）の双方が必ずこの関数を通ることで正規化規則のズレを防ぐ。
- 対象リスト側のパス（§3.7 で受け取る値）も同じ `normalize_test_path` を通し、前後の空白/改行の strip、`./` や絶対/相対パスのゆらぎを吸収してから集合比較する。
- グルーピング識別子（出力ディレクトリ名）は spec の記述（`described_class` / トップレベル `describe` の文字列など）から導出する。実装時に確定（§11）。
- ネストしたサブディレクトリ配置（`spec/system/foo/bar_spec.rb`）は初版でも file_path ベースなら正規化次第で扱える。初版は `spec/system/*_spec.rb` のフラット配置を主な前提として README に明記し、ネスト対応の網羅検証は §12 の将来課題とする。

### 3.6 アクション instrumentation

元 concern と同じく、以下の Capybara DSL メソッドをオーバーライドし `super` の前後で自動撮影する。挙動は gist を踏襲する:

- クリック系（`click_on` / `click_link` / `click_button`）は **前後両方** を撮る（クリック前の一過性の状態を取りこぼさないため）。
- それ以外（`visit` / `fill_in` / `select` / `check` / `uncheck` / `choose` / `attach_file` / `accept_confirm` / `accept_alert`）は **後のみ**。
- 各フックは「ポリシーが true の場合のみ」撮影する（per-test 判定結果をキャッシュした真偽値で分岐）。単純に前後で撮影するのではなく、撮影直前に **ページ安定待機** を挟んでから撮る。
- ファイル名は `NNN_アクション名_詳細.png`（連番 3 桁ゼロ埋め、詳細はサニタイズ）。**クリック系は「アクション名」部分に `before_`/`after_` を含む**（例: `001_before_click_on_Done.png` / `002_after_click_on_Done.png`）。詳細は§3.8参照。

**ページ安定待機**（[capybara_screenshot_helper.rb](https://github.com/SonicGarden/wlb-morning-mail/blob/release-candidate/spec/support/helpers/capybara_screenshot_helper.rb) を踏襲）:

> **実装フェーズについて**: この機構本体の実装は Phase 2（アクション instrumentation の初回移植）のスコープには含めず、専用フェーズ（[phase-8-page-stability-wait.md](phase-8-page-stability-wait.md)）に切り出すことを確定した。以下の仕様本文は SSOT として本節に残し、Phase 8 が実装時にこの記述を参照する。

- 撮影直前に、以下の両方を満たすまで一定間隔でポーリングする。満たさないまま最大試行回数に達したらタイムアウトとする。**タイムアウト時挙動は Phase 8 で確定**: テストを落とさず、warn ログ（STDERR）を出力した上で撮影を継続する（例外は投げない。opt-in の例外送出オプションも設けない）。
  - `document.getAnimations()` が返す実行中アニメーションが 0 件（設定可能な除外リストに含まれるアニメーション名は無視）。**実行中判定は `animation.playState === 'running'` のもののみをカウントする**（踏襲元にはこの判定がないが、finished/paused のアニメーションが cancel や要素除去まで `getAnimations()` の結果に残り続け、完了済みでも「実行中」と誤判定されて安定待機が毎回タイムアウトする問題を防ぐため、Phase 8 でコードレビュー指摘を受けて意図的に追加した踏襲元との差分）。
  - `MutationObserver` で監視した DOM の最終変更からの経過時間が、チェック間隔以上空いている。
- ポーリング間隔・最大試行回数・除外アニメーション名リストは設定可能にする（`configure` で上書き）。**デフォルト値は Phase 8 で確定**: ポーリング間隔 0.5 秒（`page_stability_interval`）、最大試行回数 10 回（`page_stability_max_attempts`）、除外アニメーション名は空リスト `[]`（`page_stability_excluded_animations`）。
- 監視用の `MutationObserver` は撮影のたびに setup / teardown し、状態をグローバルに残さない。
- ポリシーが false のとき（機構が無効なとき）はこの待機処理自体を一切実行しない（設計原則3のゼロオーバーヘッドを維持）。auto/manual いずれの呼び出し口も enabled ガードで待機呼び出し自体をスキップするため、ポリシー false 時は待機の JS 実行コストがゼロになる。
- 安定待機中に発生する**あらゆる例外**を rescue し、撮影は必ず継続する（待機失敗が撮影を妨げてはならないという不変条件。Phase 8 で確定、コードレビュー指摘を受けて後から `rescue StandardError` に拡大）。gem は特定ドライバに依存しないため、利用者が Cuprite(Ferrum) 等 Selenium 以外の JS ドライバを使うケースも撮影を妨げてはならない。
  - 非 JS ドライバ（Rack::Test 等、`getAnimations`/`MutationObserver` 非対応）での `Capybara::NotSupportedByDriverError` / `Selenium::WebDriver::Error::JavascriptError`（定数が存在する場合のみ）は「JS 非対応の想定内エラー」として **静かにスキップ**（warn なし）。
  - それ以外の予期しない例外（例: Cuprite/Ferrum の `Ferrum::JavaScriptError` 等）は warn ログ（STDERR）を出力してから no-op とし、ドライバ異常を可視化する。

### 3.7 対象集合の渡し方（テストファイルパス指定のみ）

対象集合は **テストファイルパスのリスト** のみで受け取る（規約マッピングや TIA は非対応）。渡し口は ENV 経由:

- `SCREENSHOT_TESTS_FILE` — 改行区切りのファイルパス一覧を書いたファイルへのパス。大量指定・CI 生成に向く。**主たる渡し口。**
- `SCREENSHOT_TESTS` — カンマ区切りの少数手動指定。補助。
- **両方指定された場合は和集合とする（確定。Phase 4 で実装済み）**。片方のみ指定でももう一方は無視されず単に空集合として扱われるだけであり、どちらの指定であっても対象集合の構築ロジックは共通。
- **`SCREENSHOT_TESTS_FILE` が指すファイルが存在しない場合は `Capybara::Storyboard::Error` を raise する**（確定）。ファイルパスの誤り（typo・CI のパス生成ミスなど）を「静かに全撮影」or「静かに0件」にせず、明示的に失敗させるための仕様。**ただしこの存在チェックは `SCREENSHOTS` が arm されているとき（`default_policy` が対象リストを読むとき）だけ走る**。`SCREENSHOTS` 未設定時は機構が無効なため対象リストを一切読まず、存在しないパスを指していても raise しない（§5「無効」ケースのゼロオーバーヘッド契約）。
- どちらも未指定なら対象リストという概念自体が構築されない（§3.4 のデフォルトポリシーが `TargetListPolicy` を合成しない）＝ `SCREENSHOTS=1` だけで全撮影という後方互換になる。一方、どちらか一方でも明示指定された場合（中身が空ファイルの場合を含む）は対象集合が構築され、その集合が空なら撮影0件になる（§3.4 参照）。

### 3.8 出力レイアウト

gist を踏襲:

```
tmp/screenshots/{GroupName}/{example_name}/{NNN_action_detail}.png
```

- `{GroupName}` は spec のグルーピング識別子（§3.5）、`{example_name}` は個々の example 名から導出（サニタイズ）。
- 出力ルートは設定可能（`configure` で `output_dir` を上書き可）。デフォルトは `Rails.root/tmp/screenshots`。
- テストごとにディレクトリを分け、連番でアクション順を保持する（エージェントが順序付き集合として読めるように）。
- `{NNN_action_detail}` の具体例（§3.6 の挙動をそのまま反映したもので、挙動変更ではなく明確化）:
  - クリック系（`click_on` 等）は前後 2 枚: `001_before_click_on_Done.png` / `002_after_click_on_Done.png`。
  - それ以外のアクションは後のみ 1 枚: `001_visit_users.png`。

---

## 4. gem 構成（ファイルツリー案）

```
capybara-storyboard/
├── capybara-storyboard.gemspec
├── Gemfile
├── README.md
├── CHANGELOG.md
├── LICENSE.txt
├── lib/
│   └── capybara/
│       ├── storyboard.rb                   # require エントリ（gem 名 → capybara/storyboard）
│       └── storyboard/
│           ├── version.rb
│           ├── configuration.rb            # 設定オブジェクト
│           ├── context.rb                  # 判定コンテキスト値オブジェクト
│           ├── test_helper.rb              # include 用モジュール（元 AutoScreenshots）
│           └── policies/
│               ├── env_policy.rb
│               └── target_list_policy.rb
├── docs/
│   ├── github-actions.md                   # CI 連携レシピ
│   └── agent-workflow.md                   # エージェント検証ワークフロー（screenshot-test 相当）
└── spec/                                    # gem 自身のテスト（RSpec）
```

- **gem 自身のテストは RSpec**（`bundle gem --test=rspec` 生成）。
- **利用者側の system test も初版は RSpec system spec のみ対応**（minitest は §12 の将来課題）。
- 依存: `capybara`（system test 前提）。Rails は「あれば `Rails.root` を使う」程度の緩い前提にできるか実装時に確認（§11）。初版は Rails/RSpec system spec を前提としてよい。
- Lint: sgcop を適用。`Rails/Env` 等の方針は既存のプロジェクト規約に合わせる。

---

## 5. 有効化モデル（まとめ）

| ケース | `SCREENSHOTS` | 対象リスト | 挙動 |
|---|---|---|---|
| 無効 | 未設定 | — | 撮影なし・フック実質ゼロオーバーヘッド |
| 全撮影（従来互換） | `1` | 未指定（`SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS` ともに未設定） | 全 system test で撮影 |
| 選択撮影 | `1` | `SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS` で指定 | 指定されたテストファイルのみ撮影。**内容が空のファイルを指定して対象集合が空集合になる場合は撮影0件**（絞り込みなしにはならない。§3.4 参照）。なお ENV 値そのものが空文字列の場合は `present?` が false になり「未指定＝全撮影」扱いになる |

`SCREENSHOTS` は「機構全体を arm するスイッチ」、対象リストは「arm 済みの中で撮る範囲を絞るフィルタ」という 2 段構成。ただし「未指定」と「明示指定した結果が空集合」は区別され、前者のみが後方互換の全撮影になる（§3.4）。

---

## 6. GitHub Actions 連携（docs/github-actions.md に記載する内容）

方針: gem は集合を受け取るだけ。CI 側で diff から対象テストファイルを抽出してファイルに書き出し、`SCREENSHOT_TESTS_FILE` で渡す。

レシピ骨子（ドキュメントに載せる YAML の意図）:

1. PR の base ブランチとの diff を取り、`spec/system/*_spec.rb` にマッチする変更ファイルのみ抽出。
2. 抽出結果を `tmp/screenshot_targets.txt` に改行区切りで書き出す（該当なしでも空ファイルで可）。
3. system test 実行時に `SCREENSHOTS=1` と `SCREENSHOT_TESTS_FILE=tmp/screenshot_targets.txt` を渡す。
4. 生成された `tmp/screenshots/**` を artifact としてアップロード（人間・エージェントが後から参照）。

注意点として文書化すること:
- 「ビューだけ変更で system test ファイル自体は不変」の PR ではこの方式は拾えない（diff にテストファイルが出ないため）。これは初版の既知の割り切り（対象はテストファイルパス指定のみ）であることを明記する。
- 対象なし（空ファイル）の場合の挙動 = 撮影 0 件（絞り込みが効いて何も撮らない）で正しい。これは `TargetListPolicy` が「集合が空なら常に false」を返す契約（§3.4）で実現される。`SCREENSHOT_TESTS_FILE` を明示指定した時点で `TargetListPolicy` が合成され、その中身が空であれば「対象0件」が確定するという理屈であり、`SCREENSHOT_TESTS_FILE` 自体を渡さない場合（全撮影）とは経路が異なる。
- `SCREENSHOT_TESTS_FILE` に指定したパスが存在しない場合は `Capybara::Storyboard::Error` が発生する（§3.7）。CI のスクリプト側でファイル生成に失敗した場合に「静かに全撮影」「静かに0件」とならず、ジョブが明示的に失敗する点に注意して運用すること（該当なしのときは空ファイルを生成する、§6 冒頭のレシピ骨子の通り）。**この検知は `SCREENSHOTS=1` を渡しているジョブでのみ働く**。`SCREENSHOTS` を設定していないジョブでは対象リストを読まないため、`SCREENSHOT_TESTS_FILE` の typo は検知されない（無効ケースは副作用ゼロが優先されるため）。

---

## 7. AI エージェント連携（docs/agent-workflow.md に記載する内容）

- PR diff 起点で対象を絞ると、スクショは「変更に関係する画面だけの順序付き少数集合」になり、エージェントへの入力として現実的なサイズに収まる（全テスト撮影だと数百枚になりエージェント読み込みが非現実的）。
- 出力構成（テストごと・連番・アクション名入りファイル名）をエージェント向け成果物としてそのまま利用する。ファイル名がアクションを説明するため、エージェントは「何の操作の直後の画面か」を把握できる。
- gist の `screenshot-test` スキル相当の手順（テスト実行 → PNG 列挙 → 1 枚ずつ視覚検証 → テスト単位でレポート → 後片付け）を、この gem 用に書き直したものを載せる。gem 化に伴い「対象テストの決め方」を diff ベースに寄せた版を記載する。

---

## 8. テスト戦略（gem 自身のテスト）

gem 自身のテストは **RSpec** で書く。

- **ポリシー単体**: `EnvPolicy` / `TargetListPolicy` を context フィクスチャで純粋にテスト（ENV や Capybara に依存しない値検証）。パス正規化のゆらぎ（`./` 付き・絶対パス・空リスト）を網羅。
- **パス導出**: RSpec の example メタデータ（`file_path` 等）→ 正規化済みテストファイルパスの導出を単体テスト。
- **instrumentation**: 実ブラウザなしで検証できるよう、Capybara DSL 呼び出しをスタブ/フェイク化し「ポリシー true のとき撮影が呼ばれ、false のとき呼ばれない」「クリック系は前後 2 回」を検証する方針。実ブラウザ結合は最小限のスモークに留める（CI コスト回避）。
- gem テストで Capybara をモックするか、ダミー Rails アプリ fixtures を持つかは実装時に判断（§11）。
- 連番・ファイル名サニタイズ・出力ディレクトリ生成のテスト。

---

## 9. gist からの移行（README に記載）

- 既存利用者向け: `AutoScreenshots` concern を削除し、`Capybara::Storyboard::TestHelper` を include する差分手順。
- ENV 名は互換維持（`SCREENSHOTS`）。従来の `SCREENSHOTS=1` はそのまま全撮影として動く。
- 新機能（対象リスト）は opt-in。既存挙動は変えない。

---

## 10. 実装フェーズ

実装フェーズの分割・依存関係・各フェーズの実装計画は [README.md](README.md)（索引）を参照。各フェーズは 1 PR を原則とし、前フェーズの受け入れ条件を満たしてから次へ進む。

---

## 11. 実装時に確定させる決定事項

各項目をどのフェーズで確定させるかは [README.md](README.md) のマッピングを参照。

- ~~合成ポリシー（Env AND TargetList）を明示クラスにするか、`policy=` に合成オブジェクト/proc を渡す形にするか。~~ **Phase 4 で確定**: 薄い lambda（`->(context) { env.call(context) && target.call(context) }`）を採用。proc が `#call(context) -> Boolean` の契約を満たすため明示クラスは不採用。`policy=` の差し替え口は不変。
- Rails 非依存にどこまで寄せるか（`Rails.root` 前提を残すか、出力ルートを注入必須にするか）。初版は Rails/RSpec system spec 前提でよいと判断しているが、gemspec の依存表明で確定する。**Phase 4 でのパス正規化基準（`normalize_test_path`）は Rails.root 相対、Rails 未定義時は `Dir.pwd` 相対にフォールバックする方式で確定。**
- gem テストで Capybara をモックするか、ダミー Rails アプリ fixtures を持つか。
- ~~`SCREENSHOT_TESTS_FILE` と `SCREENSHOT_TESTS` 併用時の統合仕様（和集合を想定）の最終確認と README 明記。~~ **Phase 4 で確定**: 和集合。README 明記は Phase 6。
- **Phase 4 で新たに確定した決定事項**: `SCREENSHOT_TESTS_FILE` に存在しないファイルパスが指定された場合は `Capybara::Storyboard::Error` を raise する（静かな全撮影/0件を防ぐため）。
- spec のグルーピング識別子（出力ディレクトリ名）の導出方法（`described_class` / トップレベル `describe` 文字列 など）。
- 被テスト側フレームワーク（RSpec system spec を初版の前提に確定するか、minitest 等も視野に入れるか）。
- CI 対象 Ruby バージョン（`required_ruby_version` と整合する matrix の選定）。
- sgcop の導入方法（Gemfile への追加方式と `.rubocop.yml` の継承構成）。
- `Gemfile.lock` を追跡するか否か（gem の慣行に倣うか、CI 再現性のため追跡するか）。
- ~~ページ安定待機（§3.6）のパラメータ（ポーリング間隔・最大試行回数・除外アニメーション名リスト・タイムアウト時挙動）。これらは Phase 8（ページ安定待機）で確定し、設定項目は Phase 5（Configuration）のスコープに反映する。~~ **Phase 8 で確定**: ポーリング間隔のデフォルトは 0.5 秒（`page_stability_interval`）、最大試行回数のデフォルトは 10 回（`page_stability_max_attempts`）、除外アニメーション名のデフォルトは空リスト `[]`（`page_stability_excluded_animations`）。タイムアウト時挙動は **warn ログ（STDERR）出力のみに留め、撮影は継続する（例外は投げない）**。踏襲元の gist 実装にある `raise` は不採用とし、opt-in の例外送出オプションも設けない（撮影機構の信頼性を優先し、待機失敗で既存 system spec を flaky 化させないため）。安定待機中に発生する**あらゆる例外**を rescue し、撮影は必ず継続する（待機失敗が撮影を妨げてはならないという不変条件）。gem は特定ドライバに依存しないため、利用者が Cuprite(Ferrum) 等 Selenium 以外の JS ドライバを使うケースでも撮影を妨げてはならない。非 JS ドライバ（Rack::Test 等、`getAnimations`/`MutationObserver` 非対応）での `Capybara::NotSupportedByDriverError` / `Selenium::WebDriver::Error::JavascriptError`（定数が存在する場合のみ）は「JS 非対応の想定内エラー」として静かにスキップ（warn なし）し、それ以外の予期しない例外（例: Cuprite/Ferrum の `Ferrum::JavaScriptError` 等）は warn ログ（STDERR）を出力してから no-op とする。**この rescue 範囲の拡大（当初の限定 rescue から `rescue StandardError` へ）はコードレビュー指摘を受けて Phase 8 実装後に確定**（詳細は [phase-8-page-stability-wait.md](phase-8-page-stability-wait.md) §8）。3 パラメータはいずれも `Capybara::Storyboard.configure` から上書き可能な `Configuration` のアクセサとして Phase 5 のスコープに反映済み（既存の `output_dir` / `policy` と同じ遅延デフォルトパターン）。

---

## 12. 将来課題（初版スコープ外）

- **minitest system test 対応**（初版は RSpec system spec のみ）。
- テストファイルのネスト配置（`spec/system/foo/bar_spec.rb`）への網羅的対応・検証。
- 「ビューのみ変更で system test 不変」PR を拾うための、変更ファイル → 対象テストのマッピング（規約 or TIA）。gem 外の別コンポーネントとして設計するのが妥当。
- visual regression（前回実行との画像 diff）。
- スクショのメタデータ（アクション種別・引数・URL 等）を JSON でサイドカー出力し、エージェントが画像に加えて構造化情報を読めるようにする。
