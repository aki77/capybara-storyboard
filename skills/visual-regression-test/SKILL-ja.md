---
name: visual-regression-test
disable-model-invocation: true
description: >-
  UI 変更（views・components・CSS・system spec）を capybara-storyboard のスクショと
  reg-cli の画像差分で before/after 比較し、意図しない見た目の変化を検出する。比較の
  baseline は引数の ref・未コミット差分の有無・base ブランチから自動で決まる。
  /visual-regression-test [ref] で明示的に呼び出す。
---

# ビジュアルリグレッションテスト（変更前 / 変更後のスクショ差分）

未コミットの差分による意図しない見た目の変化を検出する。capybara-storyboard の
スクリーンショットを **2 回** 取得し（1 回はメインリポの working tree = 「変更後」、
もう 1 回は別 worktree（起点は baseline ref。HEAD／指定 ref／base ブランチの merge-base
のいずれか）= 「変更前」）、
2 つの画像セットを `reg-cli` で差分する。出力はどの画面が変わったかを強調表示した
HTML レポートで、その変化が意図どおりかをエージェントとユーザーの双方が確認できる。

これは「今のコードのスクショを眺めるレビュー」とは異なる。単発スナップショットの
レビューは「今この画面は問題ないか？」に答えるが、このスキルは「自分の編集の前と
比べてどの画面が変わったか、その変化は意図どおりか？」に答える。後者こそが共有
パーシャル・レイアウト・CSS の変更で起きるリグレッションを実際に捕まえる。ベースライン
比較なしで「今の UI を見たいだけ」なら、それは素の `capybara-storyboard` スクショ
レビューの領分で、このスキルの対象ではない。

「変更前」の取得は別 worktree で行うため、ユーザーの元の作業ツリーには一切触れない。
stash のような退避・復元の手順が不要で、復元し損ねてユーザーの未コミット作業が消える
リスクも構造的に存在しない。

## 前提条件（開始前に確認する）

このスキルは capybara-storyboard がセットアップ済みであること（`SCREENSHOTS=1` で
スクショが撮られ、`tmp/screenshots/` 配下に出力されること）を前提とする。導入手順は
このスキル内では確認しない。

- **比較対象(baseline)を決められること。** baseline の決定は
  `scripts/resolve-baseline.sh` に委ねる（下記「baseline の決定」節、および手順 3a）。
  引数で ref が渡された場合は必ずその ref、引数なしで未コミット差分がある場合は HEAD、
  引数なしでクリーンな場合は base ブランチが baseline になる。したがって
  「クリーンだから即中止」ではない — 引数なし かつ クリーン のときは base ブランチとの
  比較（merge-base 3 点差分相当）に進む。中止するのは baseline がそもそも解決できない
  ときだけ（`resolve-baseline.sh` が exit 2）。
- **reg-cli** は `npx reg-cli` 経由で実行する（インストール不要）。レポートは
  プラットフォームの `open` コマンド（macOS）で開く。

## baseline の決定（「変更前」の起点 ref）

「変更後(after)」は常にメインリポの working tree をそのまま使う（未コミット差分が
残っていればそれ込みでよい。after 側は worktree 化しない）。「変更前(before)」の
worktree 起点となる ref だけを、次の優先順位で決める。

1. 引数で ref/ブランチが指定されている → その ref（未コミットの有無に関わらず）
2. 引数なし かつ 未コミット差分あり(`git status --short` が非空) → HEAD（従来の挙動）
3. 引数なし かつ 未コミット差分なし → base ブランチ

baseline が HEAD 以外（1 か 3）の場合、worktree の実際の起点は
`git merge-base <baseline> HEAD`（3 点差分相当）を使う。HEAD の場合は merge-base 不要で
そのまま HEAD。この判定は同梱の `scripts/resolve-baseline.sh` に集約してある
（stdout に起点 ref を 1 行返す。解決不能なら exit 2）。base ブランチ自体の解決順序も
このスクリプトが担う（概ね `github-pr-base-branch` → `vscode-merge-base` → `@{upstream}`
→ `origin/HEAD` の順。正確な順序と各情報源の扱いは `resolve-baseline.sh` を参照）。

### 引数の解釈

`/visual-regression-test [ref]` の第 1 引数を baseline ref として扱う（ブランチ名・
タグ・SHA・`origin/foo` などの任意の git ref）。以降は `resolve-baseline.sh` に
第 1 引数として渡す（引数なしなら空文字列を渡す）。

- 引数なし → baseline は自動決定（未コミット差分あり=HEAD／クリーン=base ブランチ）。
- 引数 1 個 → その ref を baseline に固定。
- 引数 2 個以上 → 最初の 1 個だけを baseline として使い、残りは無視する旨をユーザーに
  一言伝える（このスキルは単一 baseline との比較しか行わない。range の始点は
  merge-base で自動計算するため、始点・終点を両方受け取る必要はない）。
- 渡された ref が解決できない場合、`resolve-baseline.sh` が exit 2 で止まる。その ref が
  存在しない旨を伝えて中止する（勝手に別 ref にフォールバックしない — 明示指定を尊重する）。

## 手順

### 1. 対象 spec を特定する

素の `capybara-storyboard` レビューと同じ対象選定ロジックを流用し、変更した画面を
実行する system spec に絞る。全 suite を 2 回走らせてはいけない。非常に遅く、差分も
読めないほど大量になる。

- `app/views` / `app/components` / CSS が変わった場合、その画面をレンダリングする
  system spec を探す（view/component 名・コントローラアクション・ルートで検索）。
  呼び出し箇所が数えられる範囲（おおむね 10 個以下）なら、その spec を直接対象にする。
- 変更対象がレイアウトや広く使われる共有パーシャル/コンポーネントで、検索結果が
  suite の大半になる場合は列挙しない。代わりに異なる文脈をまたぐ小さな代表サンプル
  （3〜6 個程度：ログアウト画面・標準的な認証済みページ・管理画面/情報密度の高い
  ページ・狭ビューポート用 spec があればそれ）を提案し、実行前に **ユーザーに確認する**。
- system spec 自体が変更されている場合、その spec が対象。ただし差分が spec の手順
  そのものを変えていると、変更前後のスクショ列が 1:1 で対応しない。reg-cli は追加/
  削除画像として報告するが、この場合は想定内。
- ファイル内の 1 example のみが関係するなら、example 単位に絞ってもよい
  （`-e` / 行番号指定）。

まったく同じコマンドを 2 回実行するので、正確な `rspec` 対象引数（ファイルおよび/
または行番号）を記録しておく。両者が一致している必要がある。

なお対象 spec が baseline ref（手順 3a で解決する「変更前」の起点）に存在しない、または
内容が異なる可能性がある。引数なし＆未コミット差分ありのモード（baseline=HEAD）では、
新規追加した spec だけがこれに該当する。ref 指定モードや base ブランチ比較モードでは、
対象 spec 自体が baseline に無い／シグネチャ（describe/example 名）が違うこともある。
その場合の扱いは手順 3c と手順 4 の「片方にしかない画像は new/deleted」に従う。対象選定
の段階では after 側（メインリポ working tree）を基準に選べばよい。

この対象引数はメインリポと後述の worktree の両方でそのまま使える（worktree は baseline
ref の完全チェックアウトなので、パス構成はメインリポと同一）。ただし「baseline ref に
存在しない spec ファイル」を対象にした場合（新規追加した spec、または base ブランチ
比較で baseline 側にまだ無い spec）、worktree 側では load エラーになるか、before セットが
空で全画像が new 扱いになる。これは想定内の挙動でありエラーではない。base ブランチ比較
（引数なし＆クリーン、または古い ref 指定）では、対象 spec が baseline に存在していても
中身が違い、スクショの枚数や名前が after と一致しないこともある。その場合 reg-cli は
差分/追加/削除として報告するが、これも想定内。

### 2. 「変更後」セットを取得する（メインリポの working tree）

差分を適用したままの変更後状態を先に取得する。メインリポだけで完結するため、worktree を
作る前に対象 spec がそもそも通るかを確認できる。ここで失敗すれば worktree を作らずに
済み、無駄な手戻りがない。

```bash
SCREENSHOTS=1 bundle exec rspec <対象 spec>
mkdir -p tmp/vrt && rm -rf tmp/vrt/after
cp -R tmp/screenshots tmp/vrt/after
```

対象 spec が **失敗** した場合、スクショが不完全な可能性がある。失敗を報告し（失敗
自体が 1 つの発見）、部分的な取得を差分のベースラインとして扱ってよいかユーザーに
確認する。

### 3. HEAD 起点の worktree を作り、起動を確認して「変更前」を取得

#### 3a. baseline を解決し、その起点で worktree を作る

「baseline の決定」節のロジックで worktree 起点 ref を決める。引数（この呼び出しで受け
取った baseline ref。無ければ空）をそのまま `resolve-baseline.sh` に渡す。

```bash
WT=.claude/worktrees/vrt-baseline
# 引数なしなら "" を渡す。stdout に起点 ref/SHA が 1 行返る。exit 2 なら中止。
BEFORE_REF=$(.claude/skills/visual-regression-test/scripts/resolve-baseline.sh "${BASELINE_ARG:-}")
git worktree add "$WT" "$BEFORE_REF"
```

`.claude/worktrees/` は本スキル用に用意された既存の空ディレクトリを流用する。
`resolve-baseline.sh` は解決したモード（explicit / HEAD / base branch）と、HEAD 以外の
ときは適用した merge-base を **stderr** に出す。ユーザー向けレポート（手順 6）で「何を
baseline にしたか」を必ず一言添える（例: 「base ブランチ origin/release-candidate との
merge-base と比較」）。どの起点かで差分の読み方が変わるため。

起点が HEAD 以外（引数指定 or base ブランチ）の場合、worktree はその SHA/ブランチの
完全チェックアウトになる。after 側の working tree に含まれる未コミット差分＋その起点から
HEAD までの全コミットが、まとめて「変更後 − 変更前」の差分として現れる点に注意する
（HEAD 起点のときのように「未コミット差分だけ」ではない）。

#### 3b. セットアップ検知（重要・移植性の要）

worktree 内で Rails が実際に起動するかどうかを、起動可否そのもので確認する。特定の
フックの有無をチェックするのではなく「起動できるか」で判定するため、この手順は
特定プロジェクトの仕組みに依存せず、他プロジェクトにもそのまま持ち込める。

```bash
( cd "$WT" && bundle exec rails runner 'exit 0' )
```

起動に成功すれば、設定ファイル・依存関係が揃っている（worktree 作成時の自動セットアップ
が効いた、あるいは元々不要だった）とみなし、3c に進む。

起動に失敗した場合は中止する。「この worktree には設定ファイル/依存が揃っていない。
worktree 作成時の自動セットアップ（post-checkout フックなど）を用意する必要がある」旨を
ユーザーに伝え、同ディレクトリの `README.md`（本スキルの参考実装）を案内する。その上で、
作成した worktree を片付けてから終了する。

```bash
git worktree remove --force "$WT"
```

#### 3c. worktree 内で「変更前」を取得する

メインリポと同一の rspec コマンドを worktree 内で実行し、結果をメインリポの
`tmp/vrt/before` に集約する。

```bash
( cd "$WT" && SCREENSHOTS=1 bundle exec rspec <対象 spec> )
rm -rf tmp/vrt/before
cp -R "$WT/tmp/screenshots" tmp/vrt/before
```

`( cd "$WT" && ... )` のサブシェルで実行するため、メインリポ側のカレントディレクトリは
汚れない。対象 spec が失敗した場合の扱いは手順 2 の「変更後」と同様（失敗を報告し、
部分取得を使うかユーザーに確認する）。

### 4. worktree を破棄し、メインリポで reg-cli 差分

「変更前」の取得が終わったら worktree は不要なので破棄し、その後にメインリポで
差分を取る。

```bash
git worktree remove --force "$WT"
.claude/skills/visual-regression-test/scripts/reg-diff.sh tmp/vrt/after tmp/vrt/before tmp/vrt
```

`--force` を付けるのは、worktree 内で生成された untracked な `tmp/screenshots` が
残っていても（before への集約は 3c で完了済みなので）気にせず remove するため。

同梱のヘルパ（`reg-diff.sh`）は以下と等価な処理を行う。

```bash
npx reg-cli tmp/vrt/after tmp/vrt/before tmp/vrt/diff \
  --report tmp/vrt/report.html \
  --json tmp/vrt/report.json
```

- 引数順が重要: **actual（after）が第 1、expected（before）が第 2、diff ディレクトリが
  第 3。** after を actual、before を expected とすることで、レポートが「自分の差分が
  HEAD に対して何をしたか」という読み方になる。
- スクリプトの終了コード: 見た目の変化なしで `0`、差分検出で `1`（想定内の正常な結果で
  あって **エラーではない**）、実行エラー（引数不正 / 入力ディレクトリ欠如）で `2`。
  `1` は「差分あり、検証せよ」の意味であって失敗ではない。
- 同じ spec を走らせているので両セットでスクショのファイル名が一致し、reg-cli はパスで
  自動的にペアリングする。片方のセットにしかない画像（追加/削除）は new/deleted として
  報告される。これは差分が spec の手順そのものを変えたときに起きる。

### 5. 検出された差分を検証する

`tmp/vrt/report.json` を読んで変更/追加/削除された画像の一覧を取得し、変わった各画面に
ついて **実際の差分画像**（`tmp/vrt/diff/**`）と対応する before/after の PNG を読む。
ファイル名でどのアクション・画面かを判断する
（`tmp/vrt/before/{Group}/{example}/{NNN_action}.png`）。パスはすべてメインリポの
`tmp/vrt` 配下にある。

変わった各画像について、その変化が **意図どおりか** を判断する。

- その見た目の変化はコード差分がやろうとしたことと一致するか？（例: ユーザーが行った
  色・余白・ラベルの変更 → 想定どおり。）
- それとも無関係な画面がずれていないか — 共有パーシャル/レイアウトの編集が本来影響
  すべきでないページに漏れている、レイアウト崩れ、はみ出し、コンポーネントの描画差異
  など → これは報告すべきリグレッション。
- 意味のある変化を伴わない微小なサブピクセル/アンチエイリアスのノイズ → リグレッション
  ではなくノイズの可能性が高いと注記する。ノイズが支配的なら、reg-cli の閾値オプション
  （`--threshold`・`--enableAntialias` など）で再実行時に抑制できる旨を伝える。

### 6. レポートし、HTML レポートをユーザー向けに開く

手順 5 の検証が終わってから、reg-cli の HTML レポートを開く。先に開かないのは、
エージェントがまだ判断していない差分をユーザーに見せても意味が薄く、「エージェントが
検証 → 結果をユーザーに提示」という順序を崩さないため。

```bash
open tmp/vrt/report.html
```

そのうえで簡潔な文章レポートを返す。

- 変更/追加/削除された画面がそれぞれ何件か（`report.json` から）。
- 意味のある変化ごとに: どの画面か（spec + アクション/ファイル名）と、自分の判断 —
  **意図どおり**（コード変更と一致）か **リグレッションの可能性**（どこが・何がおかしく
  見えるか）か。
- 明確な結論: 「検出された変化はすべて意図した編集と整合している」か、「以下は意図
  しないリグレッションに見える: …」のいずれか。
- HTML レポートをブラウザで開いてあるので、ユーザー自身でも確認できる旨を伝える。

### 7. 出力とクリーンアップの扱い

worktree は手順 4 の時点で `git worktree remove --force` 済みであることを保証する
（手順 3b で中止した場合も同様に片付けてから終了している）。もし何らかの理由で中断し
worktree が残ってしまった場合は、`git worktree list` で `.claude/worktrees/vrt-baseline`
が残っていないか確認し、残っていれば `git worktree remove --force <path>` で片付ける。

worktree はメインリポと同じ DB（`config/database.yml`）を共有する。このスキルの実行中
（手順 2〜4）は、DB 状態が競合しうるため他のテストを並行実行しない。

base ブランチや古い ref を baseline にした場合、その ref の Rails が現在の共有 DB
スキーマ（メインリポの migration が適用済み）と食い違い、worktree 側の起動確認
（手順 3b）や rspec で失敗することがある。これは baseline が古いことに起因する想定内の
失敗で、起動確認が中止まで面倒を見る。頻発するなら baseline を HEAD 寄りに（例: 未
コミット差分のみの比較に）切り替えるようユーザーに提案する。

このスキルの最後は「HTML レポートをユーザーに見てもらう」ことなので、レポートと
それが参照する diff 画像（`tmp/vrt/`）は**そのまま残す**。ここで削除すると、ユーザーが
今まさに開いているレポートを足元から消すことになる。エージェント側から後片付けは
しない。

不要になったら次のコマンドで消せる旨だけ伝える（実行はユーザーの判断に委ねる）。

```bash
rm -rf tmp/vrt tmp/screenshots
```
