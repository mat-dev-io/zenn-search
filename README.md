# zenn-search

Zennの最新記事を収集してランキング・フィルタリングし、必要に応じてGitHub Issueへ結果を投稿するためのCLI + GitHub Actionsツールです。

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

1. リポジトリをクローンします。

```bash
git clone https://github.com/mat-dev-io/zenn-search.git
cd zenn-search
```

2. スクリプトに実行権限を付与します。

```bash
chmod +x scripts/zenn-search.sh
```

3. 必要なら `.github/workflows/zenn-search.yml` の `issue` デフォルト値やキーワードを自分用に調整します。

## ローカル実行例

まずは投稿せずに結果だけ確認します。

```bash
scripts/zenn-search.sh \
  --pages 1 \
  --max-items 3 \
  --include "GitHub Copilot,Claude" \
  --dedupe none \
  --dry-run
```

Issueに投稿する場合の例です。

```bash
scripts/zenn-search.sh \
  --repo mat-dev-io/zenn-search \
  --issue 2 \
  --pages 1 \
  --max-items 3 \
  --dedupe issue
```

## GitHub Actionsで使う

このリポジトリには、すでに実行用Workflowの `.github/workflows/zenn-search.yml` が含まれています。

使い方:

1. GitHub に push する
2. Actions タブで `Zenn Search` を開く
3. `Run workflow` から手動実行する

Workflowのデフォルト:

- `issue`: `2`
- `pages`: `5`
- `max_items`: `10`
- `dedupe`: `issue`

定期実行も有効になっており、UTC 21:00 に起動します。

## 他のリポジトリからActionとして使う

このリポジトリを公開した後は、別リポジトリから `uses:` で呼び出すこともできます。

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
