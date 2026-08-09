#!/usr/bin/env bash
set -euo pipefail

REPO="rebroad/rusty_v8"
WORKFLOW="codex-release.yml"
BRANCH="main"

usage() {
  cat <<'USAGE'
Usage: tools/publish_codex_release.sh --release-tag <tag>

Dispatch the Codex Rusty V8 producer workflow and print its run URL.
The workflow builds the fork-specific artifacts and uploads them to the
specified GitHub release. This script does not watch the run automatically.
USAGE
}

RELEASE_TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-tag)
      RELEASE_TAG="${2:-}"
      shift 2
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

command -v gh >/dev/null 2>&1 || {
  echo "ERROR: gh is required." >&2
  exit 1
}

HEAD_SHA="$(git rev-parse HEAD)"
gh workflow run "$WORKFLOW" \
  --repo "$REPO" \
  --ref "$BRANCH" \
  -f "release_tag=$RELEASE_TAG"

RUN_ID=""
for _ in {1..15}; do
  RUN_ID="$(gh run list \
    --repo "$REPO" \
    --workflow "$WORKFLOW" \
    --branch "$BRANCH" \
    --event workflow_dispatch \
    --limit 10 \
    --json databaseId,headSha \
    --jq ".[] | select(.headSha == \"$HEAD_SHA\") | .databaseId" | head -n 1 || true)"
  if [[ -n "$RUN_ID" ]]; then
    break
  fi
  sleep 2
done

if [[ -z "$RUN_ID" ]]; then
  echo "Workflow dispatched, but its run ID is not visible yet."
  echo "Run: gh run list --repo $REPO --workflow $WORKFLOW --branch $BRANCH"
  exit 0
fi

RUN_URL="https://github.com/$REPO/actions/runs/$RUN_ID"
echo "GitHub CI run: $RUN_URL"
echo "To watch: gh run watch $RUN_ID --repo $REPO --exit-status"
