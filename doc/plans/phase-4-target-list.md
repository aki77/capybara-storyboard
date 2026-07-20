# Phase 4: TargetListPolicy + 対象リスト受け取り

## 1. 目的

「機構が arm されている（Env）」だけでなく「対象テストファイルに含まれる」という条件を追加できるようにし、GitHub Actions 上で「PR 内で変更のあったシステムテストファイルのみ有効化」するユースケースを実現する。対応する仕様は overview.md §3.4（ポリシー抽象、特に `TargetListPolicy` と合成ポリシー）、§3.7（対象集合の渡し方）、§5（有効化モデルまとめ）。

## 2. スコープ

### 含むもの

- `Capybara::Storyboard::Policies::TargetListPolicy` の新規実装。
  - コンストラクタで対象テストファイルパスの集合（正規化済み）を受け取る。
  - `context.test_file` が集合に含まれれば `true`。
  - **集合が空なら常に `false`（対象0件）を返す**（確定。overview.md §3.4 改訂に合わせる）。後方互換の「対象リスト未指定＝全撮影」は `TargetListPolicy` の責務ではなく、合成側（`default_policy`）が対象リスト未指定時にそもそも `TargetListPolicy` を構築しないことで担保する。
- `SCREENSHOT_TESTS_FILE`（改行区切りファイル、主）/ `SCREENSHOT_TESTS`（カンマ区切り、補助）の読込。
- 両方指定された場合の和集合処理（確定・実装済み）。
- パス正規化（`./` 付き・絶対パス・末尾改行などのゆらぎを吸収して比較可能にする）。`Capybara::Storyboard.normalize_test_path` という単一の関数に集約し、対象リスト側・`context.test_file` 側の両方がこの関数を通ることで規則のズレを防ぐ。正規化の基準ディレクトリは Rails.root（未定義時は `Dir.pwd`）相対。
- Env AND TargetList のデフォルトポリシー合成の実装。P3 で先出しした「`configure` 未使用時のデフォルト」契約をここで確定する。合成の実装形式は薄い lambda（明示クラスは不採用）。
- `SCREENSHOT_TESTS_FILE` が指すファイルが存在しない場合に `Capybara::Storyboard::Error` を raise する実装。

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
  - **契約（確定）**: `#call(context)` は `@paths`（正規化済み集合）が空なら常に `false` を返す。`context.test_file` が `nil` のときも `false`。それ以外は `context.test_file` を `Capybara::Storyboard.normalize_test_path` で正規化した上で集合に含まれるかを判定する。
  - 「空集合＝絞り込みなし＝true」という後方互換の意味づけは `TargetListPolicy` には持たせない。空集合の `TargetListPolicy` が存在すること自体が「対象0件が明示された」状態を意味する。
- ENV からの読込（`SCREENSHOT_TESTS_FILE` / `SCREENSHOT_TESTS` の読込・和集合化・正規化）は `TargetListPolicy` の外側、`lib/capybara/storyboard.rb` の `default_policy`（と `raw_target_list` / `raw_target_list_from_file` / `raw_target_list_inline` の各プライベートメソッド）に置く。これにより `TargetListPolicy` 自体は「ENV を知らないピュアなポリシー」として単体テストしやすい。
- パス正規化ロジックは `Capybara::Storyboard.normalize_test_path`（`lib/capybara/storyboard.rb` の public メソッド）に一本化し、対象リスト側（`default_policy` 内）・`context.test_file` 側（`TargetListPolicy#call` 内）の双方がこのメソッドを呼ぶ。基準ディレクトリは `rails_root_or_pwd`（`lib/capybara/storyboard.rb` の public メソッド）が返す `Rails.root`（定義されていれば）または `Dir.pwd`。同メソッドは `Session#default_output_root` からも呼ばれるため public にしている（Rails.root への依存を1箇所へ集約）。
- 合成ポリシー（Env AND TargetList）の実装形式は**薄い lambda に確定**（明示クラスは不採用）。`default_policy` 内で `env = Policies::EnvPolicy.new` と `target = Policies::TargetListPolicy.new(targets)` を組み立て、`->(context) { env.call(context) && target.call(context) }` を返す。proc は `#call` に応答し `call(context) -> Boolean` の契約を満たすため、これで `policy=` による差し替え契約は崩れない。
- **未指定/明示指定の分岐は `default_policy` が担う**: `raw_target_list` が `nil`（`SCREENSHOT_TESTS_FILE` も `SCREENSHOT_TESTS` も未設定）を返した場合は `TargetListPolicy` を構築せず `EnvPolicy` 単体を返す。どちらか一方でも明示指定された場合（内容が空のファイルを含む。ただし ENV 値そのものが空文字列の場合は `present?` が false になり「未設定」と同じ扱いになる）は目的の集合（空集合になりうる）で `TargetListPolicy` を構築し、`EnvPolicy` と AND 合成する。
- `SCREENSHOT_TESTS_FILE` が指すパスが存在しない場合は `raw_target_list_from_file` が `Capybara::Storyboard::Error` を raise する（静かな全撮影/0件を防ぐ）。ただし `default_policy` は `SCREENSHOTS` が arm されていないときは対象リストを一切読まない（`env.call(nil)` が false なら即 `EnvPolicy` 単体を返す）ため、この存在チェックは `SCREENSHOTS` 有効時のみ走る。無効時に存在しないパスを指定していても raise しない（§5「無効」ケースのゼロオーバーヘッド契約を守るため）。

## 5. 変更ファイル（実装確定・実態と一致）

- 新規: `lib/capybara/storyboard/policies/target_list_policy.rb`
- 変更: `lib/capybara/storyboard.rb`（デフォルトポリシー構築 `default_policy`・正規化 `normalize_test_path`・基準ディレクトリ解決 `rails_root_or_pwd`・ENV 読込 `raw_target_list` 系メソッドを追加）
- 変更: `lib/capybara/storyboard/session.rb`（`default_output_root` の Rails.root フォールバックを `rails_root_or_pwd` に集約。ガード条件の重複を解消）
- 変更: `lib/capybara/storyboard/context.rb`（コメントを実態に合わせて更新。`test_file` は生の file_path を保持し、正規化は保持せず `normalize_test_path` 側の責務であることを明記）
- テスト（RSpec）:
  - 新規: `spec/capybara/storyboard/policies/target_list_policy_spec.rb`
  - 変更: `spec/capybara/storyboard_spec.rb`（デフォルトポリシー合成・和集合・空ファイル・存在しないファイルなどの結合テストを追加）
- ドキュメント: なし（本フェーズでは README・docs 本文には触れない。仕様の README 明記は P6 で行う）。

## 6. 受け入れ条件

- [ ] overview.md §5 の3ケースを再現する:
  - 無効（`SCREENSHOTS` 未設定）→ 撮影なし。
  - 全撮影（`SCREENSHOTS=1`、`SCREENSHOT_TESTS_FILE`/`SCREENSHOT_TESTS` ともに未指定）→ 全 system test で撮影。
  - 選択撮影（`SCREENSHOTS=1` + `SCREENSHOT_TESTS_FILE`/`SCREENSHOT_TESTS` 指定）→ 指定ファイルのみ撮影。
- [ ] パス正規化のゆらぎ（`./` 付き、絶対パス、末尾改行）を吸収して比較できることを検証する。
- [ ] `SCREENSHOT_TESTS_FILE` と `SCREENSHOT_TESTS` を両方指定した場合に和集合として扱われる。
- [ ] **「未指定→全撮影」と「空ファイル指定→撮影0件」を区別して検証する**（確定設計）。`SCREENSHOT_TESTS_FILE`/`SCREENSHOT_TESTS` がどちらも未指定のときは `default_policy` が `TargetListPolicy` を構築せず `EnvPolicy` 単体になり全撮影となる。一方、どちらかが明示指定され、その中身（正規化・和集合後）が空集合になる場合（空ファイル等）は `TargetListPolicy` が常に `false` を返すため撮影0件になる。旧来の「対象リストが空集合の場合は絞り込みなし=全撮影」という記述は誤りであり、採用しない。
- [ ] `TargetListPolicy` 単体テストが緑（ENV に依存しないピュアな集合判定であること、集合が空なら常に `false` を返すことを含む）。
- [ ] `SCREENSHOT_TESTS_FILE` に存在しないファイルパスが指定された場合に `Capybara::Storyboard::Error` が発生することを検証する。
- [ ] CI（spec + sgcop/rubocop）が緑。

## 7. テスト観点

- **単体**: `TargetListPolicy#call` を `Context` フィクスチャと様々な集合（空集合・単一要素・複数要素）で検証する。ENV や Capybara には一切依存しない形でテストする。
- **単体**: パス正規化ロジックを単体で検証する。`./spec/system/foo_spec.rb`・`/abs/path/spec/system/foo_spec.rb`・末尾改行付き文字列などのバリエーションを網羅する。
- **結合**: `SCREENSHOT_TESTS_FILE`・`SCREENSHOT_TESTS` の読込から正規化・和集合・`TargetListPolicy` 構築までを結合的に検証する。両方指定・片方のみ指定・両方未指定のケースを網羅する。
- **結合**: デフォルトポリシー（Env AND TargetList）が、overview.md §5 の3ケースそれぞれで正しい真偽を返すことを検証する。
- **エッジケース**:
  - `SCREENSHOT_TESTS_FILE` が指し示すファイルが空ファイルの場合（対象なし = 撮影 0 件、後方互換の「未指定→全撮影」とは異なる状態であることに注意。空ファイル指定は `default_policy` に「明示指定あり」と認識させ、`TargetListPolicy` を空集合で構築させる。その `TargetListPolicy#call` が常に `false` を返すことで撮影0件になる。overview.md §6 の「対象なし（空ファイル）の場合の挙動 = 撮影0件」に従うことを確認する）。
  - `SCREENSHOT_TESTS_FILE` 自体が未指定・`SCREENSHOT_TESTS` のみ指定など、片方のみのケース。
  - **存在しないファイルパスが `SCREENSHOT_TESTS_FILE` に指定された場合は `Capybara::Storyboard::Error` を raise する（確定）**。静かな全撮影/0件によるフェイルセーフではなく、明示的にテスト実行を失敗させる仕様であることを検証する。ただしこれは `SCREENSHOTS` が arm されているときのみ。**`SCREENSHOTS` 未設定（無効）で存在しない `SCREENSHOT_TESTS_FILE` を指定しても raise せず、機構が無効のまま（`false`）であること**も併せて検証する（ゼロオーバーヘッド契約の担保）。

## 8. リスク・決定事項

このフェーズで確定した overview.md §11 の決定事項:

- **合成ポリシーを明示クラスにするか、`policy=` に合成オブジェクト/proc を渡す形にするか**: **薄い lambda に確定**（`->(context) { env.call(context) && target.call(context) }`）。proc が `#call(context) -> Boolean` の契約を満たすため明示クラスは不採用。`policy=` による差し替え口は変更していない。
- **`SCREENSHOT_TESTS_FILE` と `SCREENSHOT_TESTS` 併用時の統合仕様（和集合）**: **確定・実装済み**（README への明記は P6）。
- **（本フェーズで新たに生じた決定事項）`SCREENSHOT_TESTS_FILE` に存在しないファイルパスが指定された場合の扱い**: **エラーにすることで確定**。`raw_target_list_from_file` が `File.exist?` を確認し、存在しなければ `Capybara::Storyboard::Error` を raise する。静かな全撮影/0件によるフェイルセーフより、CI 側のファイル生成ミスを早期に検知できることを優先した。

リスク:

- 空ファイル指定（対象ファイル0件が明示されたケース）と、そもそも `SCREENSHOT_TESTS_FILE`/`SCREENSHOT_TESTS` が未指定のケース（対象リストという概念自体が構築されない）を混同すると、overview.md §6 の意図（空ファイル=撮影0件）と後方互換要件（未指定=全撮影）が矛盾する実装になりうる。両者を明確に区別するテストケースを用意して防ぐ。

> **TODO は解決済み（本フェーズで確定）**
>
> 旧 TODO は「未指定で空集合」と「空ファイル指定で空集合」をどのコンポーネントが区別するかが仕様上未定義である、という指摘だった。この区別は**案1（合成側で分岐する）を採用して解決済み**:
>
> - **`TargetListPolicy#call` は「集合が空 → 常に `false`（対象0件）」という契約に改訂した**（overview.md §3.4 も改訂済み）。`TargetListPolicy` 単体は「未指定」と「明示指定した結果が空」を区別する必要がなく、単に「渡された集合が空なら false」というピュアな集合演算に徹する。
> - 後方互換の「未指定→全撮影」は、`lib/capybara/storyboard.rb` の `default_policy` が担う。`SCREENSHOT_TESTS_FILE`/`SCREENSHOT_TESTS` がどちらも未設定のとき（`raw_target_list` が `nil` を返すとき）は `TargetListPolicy` をそもそも構築せず `EnvPolicy` 単体を返す。どちらか一方でも明示指定されていれば（中身が空でも）`TargetListPolicy` を構築して `EnvPolicy` と AND 合成する。
> - この結果、「未指定で空集合」というケースは実行時に発生し得ない（`TargetListPolicy` は明示指定があるときにしか構築されない）ため、区別を入力側のフラグ/センチネルで持たせる案2は不要と判断し採用しなかった。
>
> overview.md §3.4/§6、本ドキュメント §2/§4/§6 は、この決定に合わせて更新済み。
- パス正規化の規則が `TargetListPolicy` 側と ENV 読込側でズレると、集合比較が一致せず「対象に含まれているのに撮影されない」不具合につながる。`Capybara::Storyboard.normalize_test_path` に正規化ロジックを一箇所に集約する実装（§4）でこれを解消した。

## 9. 参照

- overview.md §3.4（ポリシー抽象、`TargetListPolicy` と合成ポリシー）
- overview.md §3.7（対象集合の渡し方）
- overview.md §5（有効化モデルのまとめ）
- overview.md §6（GitHub Actions 連携、空ファイル時の挙動の注意点）
- 既存ファイル: `lib/capybara/storyboard/policies/env_policy.rb`（P3 で作成）、`lib/capybara/storyboard/context.rb`（P3 で作成）
