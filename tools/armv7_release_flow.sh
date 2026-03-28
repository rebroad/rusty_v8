#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: tools/armv7_release_flow.sh --release-tag <tag> [options]

Automates the armv7 release flow for rusty_v8:
1) cargo fmt
2) git add/commit (if there are tracked/untracked changes)
3) git push origin <current-branch>
4) trigger armv7-release.yml
5) optionally watch workflow to completion

Options:
  --release-tag <tag>       Required. GitHub release tag (for example: v147.0.0)
  --commit-message <msg>    Commit message. Default: "Update rusty_v8 for armv7 release"
  --repo <owner/name>       GitHub repo. Default: rebroad/rusty_v8
  --workflow <name>         Workflow file name. Default: armv7-release.yml
  --no-fmt                  Skip cargo fmt
  --no-watch                Trigger workflow and exit without watching
  -h, --help                Show this help
USAGE
}

RELEASE_TAG=""
COMMIT_MESSAGE="Update rusty_v8 for armv7 release"
REPO="rebroad/rusty_v8"
WORKFLOW="armv7-release.yml"
RUN_FMT=1
WATCH_RUN=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-tag)
      RELEASE_TAG="${2:-}"
      shift 2
      ;;
    --commit-message)
      COMMIT_MESSAGE="${2:-}"
      shift 2
      ;;
    --repo)
      REPO="${2:-}"
      shift 2
      ;;
    --workflow)
      WORKFLOW="${2:-}"
      shift 2
      ;;
    --no-fmt)
      RUN_FMT=0
      shift
      ;;
    --no-watch)
      WATCH_RUN=0
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$RELEASE_TAG" ]]; then
  echo "ERROR: --release-tag is required." >&2
  usage >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh is required." >&2
  exit 1
fi

if [[ "$RUN_FMT" -eq 1 ]] && ! command -v cargo >/dev/null 2>&1; then
  echo "ERROR: cargo is required when formatting is enabled." >&2
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" == "HEAD" ]]; then
  echo "ERROR: detached HEAD; checkout a branch first." >&2
  exit 1
fi

echo "[1/5] Repository: $REPO_ROOT"
echo "      Branch: $BRANCH"

echo "[2/5] Formatting"
if [[ "$RUN_FMT" -eq 1 ]]; then
  cargo fmt
else
  echo "      Skipped (--no-fmt)"
fi

echo "[3/5] Commit (if needed)"
git add -A
if git diff --cached --quiet; then
  echo "      No changes to commit."
else
  git commit -m "$COMMIT_MESSAGE"
fi

echo "[4/5] Push"
git push origin "$BRANCH"
HEAD_SHA="$(git rev-parse HEAD)"

echo "[5/5] Trigger workflow"
gh workflow run "$WORKFLOW" --repo "$REPO" --ref "$BRANCH" -f "release_tag=$RELEASE_TAG"

RUN_ID=""
for _ in {1..15}; do
  RUN_ID="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --branch "$BRANCH" --event workflow_dispatch --limit 1 --json databaseId,headSha --jq ".[0] | select(.headSha == \"$HEAD_SHA\") | .databaseId" || true)"
  if [[ -n "$RUN_ID" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$RUN_ID" ]]; then
  echo "Workflow dispatch succeeded, but run ID was not found yet."
  echo "Use: gh run list --repo $REPO --workflow $WORKFLOW --branch $BRANCH"
  exit 0
fi

RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
echo "Triggered run: $RUN_URL"

if [[ "$WATCH_RUN" -eq 1 ]]; then
  gh run watch "$RUN_ID" --repo "$REPO" --exit-status
else
  echo "Skipping watch (--no-watch)."
fi
