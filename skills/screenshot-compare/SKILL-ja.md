---
name: screenshot-compare
description: >-
  UI（views・components・CSS）の変更について、変更前後の比較をユーザーに見せる。
  capybara-storyboard で両方の状態のスクショを撮り、reg-cli の差分で意図しない
  変化がないことを確かめ、before / after / diff を並べた単一 HTML で提示する。
  ユーザーが新旧画面の比較や変更の見た目への影響を見たいとき（例: 「この CSS を
  変更して、新旧画面を比べて見せて」）や、CSS のように編集中以外の画面にも影響
  しうる変更のときに使う。今の画面が正しく見えるかを確認するだけなら
  capybara-storyboard を使う。before の取得方法（先撮り・worktree・stash・既存
  ディレクトリ）はエージェントが選ぶ。
---

# スクショ比較（変更前 / 変更後を並べた HTML）

UI 変更の「変更前」と「変更後」の capybara-storyboard スクショを取得し、`reg-cli` で
差分を取り、エージェント自身が検証した上で、全体を単一の自己完結 HTML としてユーザーに
提示する。画面ごとに before / after / diff を並べ、各変化へのエージェントの判定を添える。

近いスキルとの違い:

- `visual-regression-test` は明示呼び出し専用で、「変更前」は常に baseline ref の worktree で
  取得し、reg-cli 標準の HTML レポートを開く。このスキルは自動発火でき、「変更前」を最も安価で
  安全な方法で取得し、エージェントの判定付きの before/after/diff ページを作る。
- 素の `capybara-storyboard` レビューは現在のコードの単発スナップショットを見る（「今この画面は
  問題ないか？」）。このスキルは「前と比べて何が変わったか、意図どおりか？」に答え、その答えを
  ユーザーに見せる。

## 前提条件（開始前に確認する）

- capybara-storyboard が導入済みである（スクショは `SCREENSHOTS=1` で取得され `tmp/screenshots/`
  に出力される）。導入はこのスキルの範囲外。
- `npx reg-cli` が使える（インストール不要）、`ruby` が使える（HTML 生成は標準ライブラリのみ）、
  プラットフォームの `open` コマンドがある（macOS）。
- 同梱スクリプトはこの SKILL.md と同じ場所の `scripts/` にあり、スキルの配置先に依存しない。
  コマンドはプロジェクトルートで実行する。以下のコマンドの `$SKILL_DIR` は、このスキルのベース
  ディレクトリ（この SKILL.md があるディレクトリ）の絶対パスを表す。置き換えるか、同じシェル
  呼び出しの中で `SKILL_DIR` を設定する。出力先は `tmp/screenshot-compare/`:

```
tmp/screenshot-compare/
  before/        変更前のスクショ
  after/         変更後のスクショ
  diff/          reg-cli の差分画像
  report.json    reg-cli の結果（failedItems / newItems / deletedItems / passedItems）
  report.html    reg-cli 標準のレポート（ユーザーには見せない）
  notes.json     エージェントの判定（手順 7 で書く）
  compare.html   最終的な並列表示ページ（手順 8 で生成）
```

## 手順

### 1. 対象 spec を特定する

素の `capybara-storyboard` レビューと同じ要領で、変更した画面を通る system spec に絞る。
suite 全体は絶対に実行しない。

- 変更した view/component を描画する spec を探す（名前・コントローラアクション・ルートで検索）。
  呼び出し箇所が数えられる程度（目安 10 件以下）なら、それらの spec を直接対象にする。
- 共有レイアウトや広く使われるパーシャル/コンポーネントなら、文脈の異なる代表的な少数
  （目安 3〜6 個）を提案し、実行前に**ユーザーに確認**する。
- system spec 自体が変更された場合は、その spec が対象。
- 正確な `rspec` 引数を記録する。「変更前」と「変更後」は同一コマンドで実行しなければならない。

### 2. 「変更前」の取得方法を選ぶ

状況から方法を選ぶ。状況が曖昧な場合を除き、ユーザーには聞かない。

| 状況 | 方法 |
| --- | --- |
| 編集前に発火した（まだ何も変更していない。例: CSS 変更を依頼された直後） | **先撮り（pre-capture）**: 現状を撮影して `before` にコピーし、その後に編集して「変更後」を撮影する。worktree も stash も不要で最も安全。推奨。 |
| `before` と `after` のディレクトリが既にある／渡された（CI の `vr-shots` artifact、過去の撮影結果など） | **既存ディレクトリ**: 撮影をスキップする。そのまま使い（必要なら `tmp/screenshot-compare/before` と `after` にコピー）、手順 6 へ進む。 |
| 編集後で、baseline が HEAD 以外（ref 指定、またはクリーンな tree で base ブランチと比較） | **worktree のみ**（stash では再現できない）。 |
| 編集後で、未コミット差分だけを比較 | 既定は **worktree**。このプロジェクトで worktree が boot しない場合や変更が小さい場合は **stash**。 |

worktree / stash 方式では、baseline は `scripts/resolve-baseline.sh` が決める（優先順: 引数の
ref → 未コミット差分があれば HEAD → クリーンなら base ブランチ。HEAD 以外は HEAD との
merge-base に解決される。exit 2 は解決不能なので中止）。第 1 引数のみを渡す（なければ空文字列）。
2 つ以上渡された場合は残りを無視したことをユーザーに伝える。指定された ref が解決できない場合は
ユーザーに伝えて中止する。別の ref に黙ってフォールバックしない。

先撮りの場合:

```bash
rm -rf tmp/screenshots
SCREENSHOTS=1 bundle exec rspec <target specs>
mkdir -p tmp/screenshot-compare && rm -rf tmp/screenshot-compare/before
cp -R tmp/screenshots tmp/screenshot-compare/before
```

その後に編集を行い、手順 3 へ進む。

### 3. 「変更後」を取得する（既存ディレクトリ使用時はスキップ）

メインリポの working tree（変更適用済み）で実行する。過去の実行の古い画像が混入しないよう、
先に `tmp/screenshots` を削除する。

```bash
rm -rf tmp/screenshots
SCREENSHOTS=1 bundle exec rspec <target specs>
mkdir -p tmp/screenshot-compare && rm -rf tmp/screenshot-compare/after
cp -R tmp/screenshots tmp/screenshot-compare/after
```

対象 spec が**失敗**した場合、撮影が不完全な可能性がある。失敗を報告し（失敗自体が発見事項）、
部分的な撮影結果を使ってよいかユーザーに確認する。

先撮りの場合、これは編集後に行う撮影にあたる。worktree / stash 方式では、worktree や stash を
作る前に spec の失敗を検知できるよう、手順 4 より前にこれを行う。

### 4. 「変更前」を取得する（worktree / stash 方式のみ）

#### 4a. worktree

```bash
WT=.claude/worktrees/screenshot-compare-baseline
# 引数なしなら "" を渡す。stdout に起点 ref/SHA が 1 行返る。exit 2 なら中止。
BEFORE_REF=$("$SKILL_DIR"/scripts/resolve-baseline.sh "${BASELINE_ARG:-}")
git worktree add "$WT" "$BEFORE_REF"
( cd "$WT" && bundle exec rails runner 'exit 0' )
```

boot 確認に失敗したら、worktree を削除して中止する:

```bash
git worktree remove --force "$WT"
```

worktree には git が無視する設定ファイルや依存（`config/database.yml`、インストール済みの
gem/パッケージなど）が無いこと、worktree 作成時にそれらを自動セットアップする仕組みが必要なこと
をユーザーに伝える。例えば `post-checkout` フックで設定ファイルのコピーと依存インストールを行い、
`$1` が全ゼロ SHA のとき（= 新規作成された worktree のとき）だけ動かす。未コミット差分のみを
比較しているなら、代わりに stash 方式を提案する。

boot できたら、「変更前」を取得して worktree を破棄する:

```bash
( cd "$WT" && SCREENSHOTS=1 bundle exec rspec <target specs> )
rm -rf tmp/screenshot-compare/before
cp -R "$WT/tmp/screenshots" tmp/screenshot-compare/before
git worktree remove --force "$WT"
```

worktree はメインリポと DB を共有するため、他のテストを並行実行しない。古い baseline は現在の
DB スキーマと合わず boot や実行に失敗することがある。これは想定内の失敗なので、baseline を
HEAD に近づけることを提案する。

#### 4b. stash（以下の安全策をすべて講じる）

stash スタックは他の worktree や他のセッションと共有されるため、bare の `git stash` や
`git stash pop` は使わない。まず出力ディレクトリが無視されていることを確認する。無視されて
いないと `-u` が「変更後」の撮影結果ごと退避してしまうので、その場合は stash を使わない:

```bash
git check-ignore -q tmp/screenshot-compare/after || echo "not ignored: do not use stash"
```

一意なタグ付きで stash し、SHA を控える:

```bash
TAG="screenshot-compare-$(date +%s)"
git stash push -u -m "$TAG"
STASH_SHA=$(git stash list --format='%H %gs' | grep -F "$TAG" | head -1 | cut -d' ' -f1)
```

`STASH_SHA` が空ならエントリが作られていない（退避する差分がなかった）ので中止する。そうでなければ、
クリーンになった tree で「変更前」を取得する:

```bash
rm -rf tmp/screenshots
SCREENSHOTS=1 bundle exec rspec <target specs>
rm -rf tmp/screenshot-compare/before
cp -R tmp/screenshots tmp/screenshot-compare/before
```

spec の成否に関わらず、**必ず**復元して確認する:

```bash
git stash apply "$STASH_SHA"
git status --short   # 元の差分が戻ったことを確認する
```

確認できてから、タグでエントリの現在位置を引き直して drop する:

```bash
git stash list --format='%gd %gs' | grep -F "$TAG"   # -> stash@{n}
git stash drop "stash@{n}"
```

### 5. CSS 変更時のビルド済みアセットに注意する

ビルド済みアセット（`app/assets/builds`、`public/assets` など）は gitignore されていることが多く、
stash や worktree では旧状態に戻らない、あるいはそもそも存在しない。CSS 変更で差分が出るはずなのに
差分がゼロなら、まずこれを疑う。プロジェクト固有のコマンド（例: `bin/rails assets:precompile`、
`yarn build:css`）でアセットを再ビルドし、撮り直す。

### 6. reg-cli で差分を取る

```bash
"$SKILL_DIR"/scripts/reg-diff.sh \
  tmp/screenshot-compare/after tmp/screenshot-compare/before tmp/screenshot-compare
```

- 引数の順序が重要: **after（actual）が第 1、before（expected）が第 2、出力ディレクトリが第 3。**
- 終了コード: `0` は見た目の変化なし、`1` は差分検出（想定内で**エラーではない**）、`2` は実行エラー
  （引数不正・ディレクトリ不在）。
- 片側にしかない画像は new/deleted として報告される。変更で spec 自体の手順が変わった場合や、
  クエリ文字列中の ID（例: `/search?user_id=42`）でファイル名がずれた場合に起こる。`visit` の
  パスセグメント中のレコード ID は gem が `N` に正規化済みなので原因にならない。

### 7. 差分を検証し、`notes.json` を書く

`tmp/screenshot-compare/report.json`（`failedItems`、`newItems`、`deletedItems`）を読む。
該当する各画像について、diff 画像（`diff/**`）と対応する before/after の PNG
（`before/{Group}/{example}/{NNN_action}.png`）を実際に読み、1 枚ずつ判定する:

- **intended**: 見た目の変化がコード変更の意図と一致している。
- **regression**: 無関係な画面がずれた、または何かが壊れた。レイアウト崩れ、はみ出し、共有
  パーシャル/レイアウト/CSS の編集が影響すべきでないページに漏れた、など。
- **noise**: サブピクセルやアンチエイリアスの差で、意味のある変化がない。ノイズが支配的なら、
  再実行時に reg-cli の `--threshold` / `--enableAntialias` オプションが使えることに触れる。

判定を `tmp/screenshot-compare/notes.json` に書く。キーは `report.json` の item と同じ相対パス。
passed の画像には書かなくてよい。

```json
{
  "summary": "Overall conclusion (optional)",
  "items": {
    "Group/example/003_after_click_on_Done.png": {
      "verdict": "intended | regression | noise",
      "comment": "Why"
    }
  }
}
```

### 8. HTML を生成して表示し、報告する

ユーザーが未判定の差分を見ることがないよう、手順 7 の検証が終わってから生成する。

```bash
ruby "$SKILL_DIR"/scripts/build-html.rb --dir tmp/screenshot-compare \
  [--notes PATH] [--title TEXT] [--out PATH]
open tmp/screenshot-compare/compare.html
```

`--notes` の既定は `<dir>/notes.json`、`--out` の既定は `<dir>/compare.html`。ページは全画像を
spec/example ごとに 3 列（before / after / diff）で並べ、changed / new / deleted の画面にバッジを
付け、`notes.json` の判定とコメントを表示し、変化のない画面は折りたたむ（before と after が同一なので 1 枚だけ表示する）。画像をクリックすると
オーバーレイで原寸表示できる（背景・×ボタン・Esc で閉じる）。画像は base64 で単一 HTML に
埋め込まれるため、画像が多いとサイズが大きくなる（50 MB を超えるとスクリプトが警告する）。

その後、簡潔な文章で報告する:

- 変更/追加/削除された画面の数（`report.json` から）。
- 主要な変化ごとに、どの画面か、およびその判定。
- 明確な結論: 「すべての変化が意図した編集と一致している」または「以下はリグレッションの疑いがある: ...」。
- 「変更前」をどの方法で取得したか（先撮り / baseline 付き worktree / stash / 既存ディレクトリ）。
- ユーザーが確認できるよう HTML をブラウザで開いてあること。

### 9. 出力とクリーンアップ

`tmp/screenshot-compare/` はユーザーが閲覧中なので残す。不要になったら削除できることだけを伝える:

```bash
rm -rf tmp/screenshot-compare tmp/screenshots
```

`git worktree list` で `.claude/worktrees/screenshot-compare-baseline` の取り残しがないか確認し、
あれば `git worktree remove --force <path>` で除去する。stash 方式を使った場合は、エントリが
drop 済みであることを確認する。
