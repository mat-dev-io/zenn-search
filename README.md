# zenn-search

Zennの最新記事を収集してランキング・フィルタリングし、必要に応じてGitHub Issueへ結果を投稿するためのCLI + GitHub Actionsツールです。

このリポジトリの主な使い方は、ユーザー自身のリポジトリ配下に `zenn-search` を配置し、そのリポジトリのIssueへ履歴を蓄積する運用です。

## 含まれるもの

- `scripts/zenn-search.sh`: 記事収集・スコアリング・Issue投稿を行うCLI
- `action.yml`: `scripts/zenn-search.sh` を呼び出す Composite Action
- `.github/workflows/ci.yml`: シェル品質チェックとスモークチェックのためのCI
- `.github/workflows/zenn-search.yml`: 手動実行と定期実行のためのWorkflow

## 要件

- `bash`
- `python3`
- `gh`

GitHub Actions の `ubuntu-latest` では、通常これらは利用可能です。ローカル実行時は `gh auth login` を済ませてください。

## セットアップ

1. あなたの運用リポジトリ直下に `zenn-search` を配置します。

```bash
cd /path/to/your-repo
git clone https://github.com/mat-dev-io/zenn-search.git tools/zenn-search
cd tools/zenn-search
```

2. スクリプトに実行権限を付与します。

```bash
chmod +x scripts/zenn-search.sh
```

3. あなたのリポジトリ側に Workflow を追加します。

例: `.github/workflows/zenn-search.yml`

```yaml
name: Zenn Search

on:
  workflow_dispatch:
    inputs:
      issue:
        description: "Post results to this issue number"
        required: true
        default: "2"
      pages:
        description: "How many pages to scan"
        required: false
        default: "5"
      max_items:
        description: "How many items to post"
        required: false
        default: "10"
      include:
        description: "Include keywords CSV"
        required: false
        default: "GitHub Copilot, GitHub Actions, Agent Skills, AI, Claude, automation"
      exclude:
        description: "Exclude keywords CSV"
        required: false
        default: ""
      dedupe:
        description: "Dedupe mode: local|issue|none"
        required: false
        default: "issue"
      dry_run:
        description: "Do not post comment (print only)"
        required: false
        type: boolean
        default: false

permissions:
  contents: read
  issues: write

jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ./tools/zenn-search
        with:
          repo: ${{ github.repository }}
          issue: ${{ github.event.inputs.issue || '2' }}
          pages: ${{ github.event.inputs.pages || '5' }}
          max_items: ${{ github.event.inputs.max_items || '10' }}
          include: ${{ github.event.inputs.include || 'GitHub Copilot, GitHub Actions, Agent Skills, AI, Claude, automation' }}
          exclude: ${{ github.event.inputs.exclude || '' }}
          dedupe: ${{ github.event.inputs.dedupe || 'issue' }}
          dry_run: ${{ github.event.inputs.dry_run || 'false' }}
```

## ローカル実行例

まずは投稿せずに結果だけ確認します。

あなたの運用リポジトリ直下から実行します。

```bash
tools/zenn-search/scripts/zenn-search.sh \
  --pages 1 \
  --max-items 3 \
  --include "GitHub Copilot,Claude" \
  --dedupe none \
  --dry-run
```

Issueに投稿する場合の例です。

```bash
tools/zenn-search/scripts/zenn-search.sh \
  --repo <your-owner>/<your-repo> \
  --issue 2 \
  --pages 1 \
  --max-items 3 \
  --dedupe issue
```

## GitHub Actionsで使う

あなたのリポジトリに追加した Workflow から、`./tools/zenn-search` を呼び出します。

使い方:

1. あなたのリポジトリに `tools/zenn-search` を含めて push する
2. Actions タブで `Zenn Search` を開く
3. `Run workflow` から手動実行する

Workflowのデフォルト:

- `issue`: `2`
- `pages`: `5`
- `max_items`: `10`
- `dedupe`: `issue`

定期実行も有効になっており、UTC 21:00 に起動します。

## 履歴のたまり方

実行結果は、Workflowで指定したあなた自身のリポジトリのIssueにコメントとして蓄積されます。

- `repo: ${{ github.repository }}` を指定すると、実行元リポジトリのIssueに投稿されます。
- `issue: "2"` を指定すると、そのIssueに継続して履歴が積み上がります。
- `dedupe: issue` を使うと、同じIssueの過去コメントを見て既出URLを除外します。

## 他のリポジトリからActionとして使う

必要であれば、このリポジトリを公開した後に別リポジトリから `uses:` で呼び出すこともできます。ただし主運用は、あなたのリポジトリ配下に `tools/zenn-search` として配置する方式です。

```yaml
jobs:
  run:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mat-dev-io/zenn-search@v0
        with:
          repo: ${{ github.repository }}
          issue: "2"
          pages: "5"
          max_items: "10"
          dedupe: "issue"
          dry_run: "false"
```

## 注意点

- GitHub Actions のような揮発環境では `dedupe: issue` を使ってください。
- ローカルで繰り返し実行する場合は `dedupe: local` を使ってください。
- コメント投稿時のみ `issues: write` 権限が必要です。
- Zenn側のHTML/JSON構造が変わると取得処理が壊れる可能性があります。

## ライセンス

好みのライセンスを選択してください。一般的にはMITで十分です。
