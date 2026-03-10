# zenn-search

GitHub Action + CLI wrapper to collect recent articles from Zenn, rank/filter them, and optionally post results to a GitHub Issue.

## What this template includes

- `action.yml`: Composite Action wrapper for `scripts/zenn-search.sh`
- `.github/workflows/ci.yml`: CI for shell quality and smoke checks
- This README with copy-paste setup

## Requirements

- `scripts/zenn-search.sh` exists in this repository
- Script supports these options:
  - `--url --pages --max-items --include --exclude --dedupe`
  - `--repo --issue --dry-run`
  - `--output --state-path --seen-output`
  - optional: `--profile`
- Runtime tools in GitHub runner:
  - `bash`
  - `python3`
  - `gh` (already available on `ubuntu-latest`)

## Quick setup

1. Copy files from this template:

```bash
cp action.yml <your-new-repo>/action.yml
mkdir -p <your-new-repo>/.github/workflows
cp .github/workflows/ci.yml <your-new-repo>/.github/workflows/ci.yml
cp README.md <your-new-repo>/README.md
```

2. Place your script at:

```text
scripts/zenn-search.sh
```

3. Commit and push.

## Example workflow using this action

Create `.github/workflows/zenn-search.yml` in your new repository:

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

## Notes

- Use `dedupe: issue` for ephemeral runners (best for GitHub Actions).
- Use `dedupe: local` for local repeated runs.
- Keep permissions minimal: `issues: write` only when posting comments.

## License

Choose your preferred license (MIT is common for this type of utility).
