#!/usr/bin/env bash
set -euo pipefail

repo=""
issue_number=""
list_url="https://zenn.dev/articles"
pages=5
max_items=10
include_keywords=""
exclude_keywords=""
dedupe="local"
dry_run=0

usage() {
  cat <<'EOF'
Usage:
  scripts/zenn-search.sh [--url URL] [--pages N] [--max-items N]
                         [--include CSV] [--exclude CSV]
                         [--dedupe local|issue|none]
                         [--repo owner/name --issue N]
                         [--dry-run]

やること（フィード不使用）:
  Zenn の記事一覧ページ（デフォルト: https://zenn.dev/articles ）を取得し、
  Next.js の埋め込みJSON（__NEXT_DATA__）から新着記事メタデータを抽出します。

  その後、include/exclude キーワードでスコアリングし、
  上位 N 件を data/zenn/search/comment.md に出力。
  --repo と --issue を指定した場合は、Issue にコメント投稿します。

重複抑止:
  `--dedupe local`（デフォルト）: .local/zenn-search-state.json に既出URLを保存
  `--dedupe issue`              : 指定Issueの過去コメント本文から既出URLを抽出
  `--dedupe none`               : 重複抑止しない

例:
  # まずは生成だけ（投稿しない）
  scripts/zenn-search.sh --include "LLM,Claude,MCP" --dry-run

  # 2ページ分（約100件弱）から選ぶ
  scripts/zenn-search.sh --pages 3 --include "TypeScript,React,Next.js" --dry-run

  # Issue #4 に投稿
  scripts/zenn-search.sh --include "LLM,Claude" --repo mat-dev-io/LIFE --issue 4

  # GitHub Actions 等（実行環境が揮発）での重複抑止: Issueコメントから既出URLを拾う
  scripts/zenn-search.sh --include "LLM,Claude" --repo mat-dev-io/LIFE --issue 4 --dedupe issue
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"; shift 2 ;;
    --issue)
      issue_number="$2"; shift 2 ;;
    --url)
      list_url="$2"; shift 2 ;;
    --pages)
      pages="$2"; shift 2 ;;
    --max-items)
      max_items="$2"; shift 2 ;;
    --include)
      include_keywords="$2"; shift 2 ;;
    --exclude)
      exclude_keywords="$2"; shift 2 ;;
    --dedupe)
      dedupe="$2"; shift 2 ;;
    --dry-run)
      dry_run=1; shift 1 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 が見つかりません。" >&2
  exit 1
fi

mkdir -p .local data/zenn/search
state_path=".local/zenn-search-state.json"
comment_path="data/zenn/search/comment.md"

dedupe_mode="$dedupe"
seen_path=""

case "$dedupe_mode" in
  local|issue|none)
    ;;
  *)
    echo "Invalid --dedupe: $dedupe_mode (expected: local|issue|none)" >&2
    exit 2
    ;;
esac

if [[ "$dedupe_mode" == "issue" ]]; then
  if [[ -z "$issue_number" || -z "$repo" ]]; then
    echo "--dedupe issue を使う場合は --repo と --issue を両方指定してください。" >&2
    exit 2
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo "gh が見つかりません。先にインストールしてください。" >&2
    echo "Ubuntu例: sudo apt update && sudo apt install -y gh" >&2
    exit 2
  fi

  if ! gh auth status -h github.com >/dev/null 2>&1; then
    echo "Not logged in. Run: gh auth login -h github.com -p https" >&2
    exit 2
  fi

  seen_path="data/zenn/search/seen-from-issue.txt"

  gh api --paginate "repos/${repo}/issues/${issue_number}/comments" --jq '.[].body' \
    | python3 /dev/fd/3 "$seen_path" 3<<'PY'
import re
import sys

out_path = sys.argv[1]
text = sys.stdin.read()

# Broad match, then trim trailing punctuation that often follows URLs in Markdown.
raw = re.findall(r"https?://zenn\.dev/[^\s\]\)>\"]+", text)

urls = []
seen = set()
for u in raw:
    u = u.rstrip(").,;!')\"]")
    if u not in seen:
        urls.append(u)
        seen.add(u)

with open(out_path, 'w', encoding='utf-8') as f:
    for u in urls:
        f.write(u + '\n')
PY
fi

python3 - "$list_url" "$pages" "$state_path" "$comment_path" "$max_items" "$include_keywords" "$exclude_keywords" "$dedupe_mode" "$seen_path" <<'PY'
import json
import math
import re
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

list_url = sys.argv[1].strip()
pages = int(sys.argv[2])
state_path = sys.argv[3]
comment_path = sys.argv[4]
max_items = int(sys.argv[5])
include_csv = sys.argv[6].strip()
exclude_csv = sys.argv[7].strip()
dedupe_mode = sys.argv[8].strip()
seen_path = sys.argv[9].strip()


def fetch_text(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(
        url,
        headers={
            'User-Agent': 'LIFE/zenn-search (+https://github.com/mat-dev-io/LIFE)'
        },
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        charset = resp.headers.get_content_charset() or 'utf-8'
        return resp.read().decode(charset, errors='replace')


def extract_next_data(html: str) -> dict:
    m = re.search(r'<script[^>]+id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not m:
        raise ValueError('no __NEXT_DATA__ found')
    return json.loads(m.group(1))


def parse_iso_datetime(s: str) -> datetime | None:
    s = (s or '').strip()
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace('Z', '+00:00'))
    except Exception:
        return None


def normalize_keywords(csv: str) -> list[str]:
    return [k.strip().lower() for k in (csv or '').split(',') if k.strip()]


def load_state(path: str) -> dict:
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return json.load(f) or {}
    except FileNotFoundError:
        return {}
    except Exception:
        return {}


def save_json(path: str, obj: dict) -> None:
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)


def to_abs_url(base: str, path: str) -> str:
    if not path:
        return ''
    return urllib.parse.urljoin(base, path)


def clamp(n: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, n))


def load_seen_from_file(path: str) -> set[str]:
  if not path:
    return set()
  try:
    with open(path, 'r', encoding='utf-8') as f:
      return {line.strip() for line in f if line.strip()}
  except FileNotFoundError:
    return set()
  except Exception:
    return set()


include = normalize_keywords(include_csv)
exclude = normalize_keywords(exclude_csv)

state = {}
seen: set[str]
if dedupe_mode == 'local':
  state = load_state(state_path)
  seen = set(state.get('seen', []) or [])
elif dedupe_mode == 'issue':
  seen = load_seen_from_file(seen_path)
else:
  seen = set()

base = 'https://zenn.dev'

candidates: list[dict] = []
for page in range(1, pages + 1):
    url = list_url
    if page > 1:
        sep = '&' if ('?' in url) else '?'
        url = f'{url}{sep}page={page}'

    html = fetch_text(url)
    data = extract_next_data(html)

    # /articles は props.pageProps.articles を持つ
    page_props = (((data.get('props') or {}).get('pageProps') or {}))
    articles = page_props.get('articles') or []

    for a in articles:
        title = (a.get('title') or '').strip()
        path = (a.get('path') or '').strip()
        if not title or not path:
            continue

        link = to_abs_url(base, path)
        if not link:
            continue
        if link in seen:
            continue

        user = (a.get('user') or {})
        username = (user.get('username') or '').strip()

        publication = (a.get('publication') or {})
        pub_slug = (publication.get('slug') or '').strip()
        pub_name = (publication.get('name') or '').strip()

        liked = a.get('likedCount')
        liked_count = int(liked) if isinstance(liked, int) else 0

        published_at = (a.get('publishedAt') or '').strip()
        published_dt = parse_iso_datetime(published_at)

        candidates.append(
            {
                'title': title,
                'link': link,
                'publishedAt': published_at,
                'publishedDt': published_dt,
                'likedCount': liked_count,
                'username': username,
                'pubSlug': pub_slug,
                'pubName': pub_name,
            }
        )

# de-dup by link preserving order
uniq: list[dict] = []
seen_links: set[str] = set()
for c in candidates:
    if c['link'] in seen_links:
        continue
    uniq.append(c)
    seen_links.add(c['link'])

now = datetime.now(timezone.utc)


def score(item: dict) -> float:
    title = item.get('title', '')
    title_l = title.lower()

    # Hard reject
    for k in exclude:
        if k and k in title_l:
            return -1e9

    s = 0.0

    # Keyword match (title)
    if include:
        for k in include:
            if k and k in title_l:
                s += 10.0

    # Popularity (soft)
    liked = int(item.get('likedCount') or 0)
    s += math.log1p(max(0, liked))

    # Recency (soft): within 7 days
    dt = item.get('publishedDt')
    if isinstance(dt, datetime):
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        age_days = (now - dt.astimezone(timezone.utc)).total_seconds() / 86400.0
        s += clamp(7.0 - age_days, 0.0, 7.0) / 2.0

    # If include keywords are set and none matched, down-rank
    if include and not any(k in title_l for k in include):
        s -= 5.0

    return s


ranked = []
for c in uniq:
    sc = score(c)
    if sc <= -1e8:
        continue
    ranked.append((sc, c))

ranked.sort(key=lambda x: x[0], reverse=True)

picked = [it for _, it in ranked[:max_items]]

lines: list[str] = []
lines.append(f'- Source: {list_url} (pages={pages})')
lines.append(f'- Include: {", ".join(include) if include else "(none)"}')
lines.append(f'- Exclude: {", ".join(exclude) if exclude else "(none)"}')
lines.append('')

if not picked:
    lines.append('- (該当なし)')
else:
    for it in picked:
        meta = []
        if it.get('username'):
            meta.append(f"@{it['username']}")
        if it.get('pubName'):
            meta.append(it['pubName'])
        if it.get('likedCount'):
            meta.append(f"♥{it['likedCount']}")
        if it.get('publishedAt'):
            meta.append(it['publishedAt'][:10])
        suffix = f" ({' / '.join(meta)})" if meta else ''
        lines.append(f"- [{it['title']}]({it['link']}){suffix}")

md = '\n'.join(lines).rstrip() + '\n'

with open(comment_path, 'w', encoding='utf-8') as f:
    f.write(md)

# Update state with picked URLs (local mode only)
if dedupe_mode == 'local':
  if picked:
    cur = list(state.get('seen', []) or [])
    cur_set = set(cur)
    for it in picked:
      link = it.get('link') or ''
      if link and link not in cur_set:
        cur.append(link)
        cur_set.add(link)
    state['seen'] = cur[-1000:]

  save_json(state_path, state)
PY

if [[ -n "$issue_number" || -n "$repo" ]]; then
  if [[ -z "$issue_number" || -z "$repo" ]]; then
    echo "Issue に投稿する場合は --repo と --issue を両方指定してください。" >&2
    exit 2
  fi

  if ! command -v gh >/dev/null 2>&1; then
    echo "gh が見つかりません。先にインストールしてください。" >&2
    echo "Ubuntu例: sudo apt update && sudo apt install -y gh" >&2
    exit 2
  fi

  if ! gh auth status -h github.com >/dev/null 2>&1; then
    echo "Not logged in. Run: gh auth login -h github.com -p https" >&2
    exit 2
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    echo "DRY RUN"
    echo "repo:  $repo"
    echo "issue: $issue_number"
    echo
    cat "$comment_path"
    exit 0
  fi

  gh issue comment --repo "$repo" "$issue_number" --body-file "$comment_path"
  echo "posted: $repo#$issue_number"
else
  if [[ "$dry_run" -eq 1 ]]; then
    echo "DRY RUN"
  fi
  cat "$comment_path"
  echo
  if [[ "$dedupe_mode" == "local" ]]; then
    echo "(generated: $comment_path , state: $state_path)"
  else
    echo "(generated: $comment_path)"
  fi
fi
