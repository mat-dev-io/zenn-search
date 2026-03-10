# zenn-search

Zennの最新記事を収集してランキング・フィルタリングし、必要に応じてGitHub Issueへ結果を投稿するためのGitHub Action + CLIラッパーです。

## このテンプレートに含まれるもの

- `action.yml`: `scripts/zenn-search.sh` を呼び出す Composite Action ラッパー
- `.github/workflows/ci.yml`: シェル品質チェックとスモークチェックのためのCI
- このREADME（そのままコピーして使えるセットアップ手順付き）

## 要件

- このリポジトリに `scripts/zenn-search.sh` が存在すること
- スクリプトが次のオプションをサポートしていること:
  - `--url --pages --max-items --include --exclude --dedupe`
  - `--repo --issue --dry-run`
  - `--output --state-path --seen-output`
  - 任意: `--profile`
- GitHub runner 上で利用できる実行ツール:
  - `bash`
  - `python3`
  - `gh`（`ubuntu-latest` では標準で利用可能）

## クイックセットアップ

1. このテンプレートからファイルをコピーします:

```bash
cp action.yml <your-new-repo>/action.yml
mkdir -p <your-new-repo>/.github/workflows
cp .github/workflows/ci.yml <your-new-repo>/.github/workflows/ci.yml
cp README.md <your-new-repo>/README.md
```

2. スクリプトを次の場所に配置します:

```text
scripts/zenn-search.sh
```

3. コミットしてプッシュします。

## このActionを使うワークフロー例

新しいリポジトリに `.github/workflows/zenn-search.yml` を作成します:

```yaml
name: Zenn Search

on:
  workflow_dispatch:
    inputs:
      issue:
        description: "Issue number"
        required: true
        default: "1"
      pages:
        description: "Pages to scan"
        required: false
        default: "5"
      max_items:
        description: "Items to output"
        required: false
        default: "10"
      dry_run:
        description: "Do not post, print only"
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
      - uses: ./
        with:
          repo: ${{ github.repository }}
          issue: ${{ github.event.inputs.issue }}
          pages: ${{ github.event.inputs.pages }}
          max_items: ${{ github.event.inputs.max_items }}
          include: "GitHub Copilot, GitHub Actions, Agent Skills, AI, Claude, automation"
          dedupe: "issue"
          dry_run: ${{ github.event.inputs.dry_run }}
```

## 注意点

- 一時的なランナーでは `dedupe: issue` を使ってください（GitHub Actionsに最適）。
- ローカルで繰り返し実行する場合は `dedupe: local` を使ってください。
- 権限は最小限にしてください。コメント投稿時のみ `issues: write` が必要です。

## ライセンス

好みのライセンスを選択してください（この種のユーティリティではMITが一般的です）。
