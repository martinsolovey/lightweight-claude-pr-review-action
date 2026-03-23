#!/bin/bash

# Resolves the base SHA for git diff:
#   - If INCREMENTAL != true, exports DIFF_BASE_SHA=BASE_SHA (full diff, current behavior).
#   - If INCREMENTAL == true, searches the PR comments for the most recent
#     <!-- pr-reviewer-sha: <sha> --> marker. If found and the SHA is reachable
#     in the local git history, uses it as the diff base (incremental diff).
#     Falls back to BASE_SHA on any error (missing marker, force push, etc.).

set -e

INCREMENTAL="${INCREMENTAL:-false}"
BASE_SHA="${BASE_SHA:-}"
HEAD_SHA="${HEAD_SHA:-}"

if [[ "$(echo "$INCREMENTAL" | tr '[:upper:]' '[:lower:]')" != "true" ]]; then
  echo "DIFF_BASE_SHA=${BASE_SHA}" >> "$GITHUB_ENV"
  echo "Incremental review disabled. Using PR base SHA: ${BASE_SHA}"
  exit 0
fi

# Fetch all comments on the PR and look for the latest marker.
COMMENTS=$(curl -s \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${REPOSITORY}/issues/${PR_NUMBER}/comments?per_page=100")

# Extract the last SHA marker from all comments (grep last match).
LAST_SHA=$(echo "$COMMENTS" \
  | jq -r '.[].body' \
  | grep -oP '(?<=<!-- pr-reviewer-sha: )[a-f0-9]+(?= -->)' \
  | tail -1)

if [[ -z "$LAST_SHA" ]]; then
  echo "No previous review marker found. Using full diff from PR base SHA: ${BASE_SHA}"
  echo "DIFF_BASE_SHA=${BASE_SHA}" >> "$GITHUB_ENV"
  exit 0
fi

# Validate the SHA is reachable in the local checkout (guards against force pushes / rebases).
if ! git cat-file -e "${LAST_SHA}^{commit}" 2>/dev/null; then
  echo "Marker SHA ${LAST_SHA} not found in local history (possible force push). Falling back to PR base SHA: ${BASE_SHA}"
  echo "DIFF_BASE_SHA=${BASE_SHA}" >> "$GITHUB_ENV"
  exit 0
fi

echo "Incremental review: diffing from ${LAST_SHA} to ${HEAD_SHA}"
echo "DIFF_BASE_SHA=${LAST_SHA}" >> "$GITHUB_ENV"
