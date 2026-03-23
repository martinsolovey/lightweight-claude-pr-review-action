# JurojinPoker-PR-Reviewer

GitHub Action that reviews pull requests using **OpenAI Chat Completions** (`/v1/chat/completions`). It reads the PR diff, sends instructions plus the diff to the model, and posts the reply as a **comment on the pull request** (issue comments API), same pattern as [ProductDock/openai-pr-review-action](https://github.com/productdock/openai-pr-review-action).

**You must run `actions/checkout` before this composite action** so `prompt_file` (if used) can be read from your repo. `prompt_style` uses built-in prompts from the action—no files needed in your repository.

👉 **Quick setup:** See [INSTALL-CLIENT.md](INSTALL-CLIENT.md) for a step-by-step guide to add this action to any repository.

## Features

- Extracts the code diff between base and head SHAs (same as upstream).
- Resolves review instructions: **prompt_style** (team, technical, users) uses bundled prompts; **prompt_file** overrides with a custom file from your repo; or omit both for legacy behavior.
- Optional **GitHub Flavored Markdown** in the model output (default on), or plain text.
- Posts the summary as a PR comment.
- **Incremental review** (default on): each comment embeds a hidden SHA marker so subsequent pushes to the same PR are reviewed only from where the last review left off, not from scratch.

## Prerequisites

- OpenAI API key
- GitHub token (typically `${{ github.token }}` in the workflow)
- Repository checkout with `fetch-depth: 0` so `git diff` across the PR range works
- On the runner, **`jq`** and **`curl`** must be available (included on GitHub-hosted `ubuntu-latest`; install `jq` locally if you run Bats tests on a minimal environment).

## Usage

Minimal workflow (named prompt style `team`):

```yaml
name: PR review (OpenAI)

on:
  pull_request:
    types: [opened, reopened, synchronize]

permissions:
  contents: read
  pull-requests: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Review PR with OpenAI
        uses: YOUR_ORG/JurojinPoker-PR-Reviewer@v1
        with:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          GITHUB_TOKEN: ${{ github.token }}
          REPOSITORY: ${{ github.repository }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          prompt_style: team
```

Replace `YOUR_ORG/JurojinPoker-PR-Reviewer@v1` with your published action reference.

### Custom prompt file (override)

Use a file from your repository to override the built-in prompts:

```yaml
with:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  GITHUB_TOKEN: ${{ github.token }}
  REPOSITORY: ${{ github.repository }}
  PR_NUMBER: ${{ github.event.pull_request.number }}
  prompt_file: .github/pr-review-prompts/technical.txt
```

The file must exist in your repo (path relative to repo root).

### Legacy behavior (closest to upstream)

Use the built-in ProductDock-style instruction text and plain output:

```yaml
with:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  GITHUB_TOKEN: ${{ github.token }}
  REPOSITORY: ${{ github.repository }}
  PR_NUMBER: ${{ github.event.pull_request.number }}
  use_markdown: false
```

Do not set `prompt_file` or `prompt_style` to get the legacy instruction block.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `OPENAI_API_KEY` | yes | — | OpenAI API key. |
| `GITHUB_TOKEN` | yes | — | Token for the GitHub API (e.g. `${{ github.token }}`). |
| `REPOSITORY` | yes | — | `owner/repo`. |
| `PR_NUMBER` | yes | — | Pull request number. |
| `GPT_MODEL` | no | `gpt-4o-mini` | Chat model name. |
| `MAX_TOKENS` | no | `500` | Max tokens for the completion. Increase if comments are truncated (e.g. `1024`). |
| `prompt_file` | no | *(empty)* | Path **relative to repo root** to a custom instruction file. Highest precedence; overrides `prompt_style`. If set and missing, the job **fails**. |
| `prompt_style` | no | *(empty)* | One of `team`, `technical`, `users`. Uses **built-in** prompts bundled with the action. No files needed in your repo. Used only if `prompt_file` is empty. |
| `use_markdown` | no | `true` | If `true`, instructions ask for concise **GFM** (e.g. `##` headings, lists). If `false`, instructions ask for plain concise text. |
| `incremental_review` | no | `true` | If `true`, each run reviews only the commits added since the previous review. The last reviewed SHA is embedded as a hidden HTML marker in the comment. Falls back to a full diff when no prior review exists or the SHA is no longer reachable (e.g. after a force push). Set to `false` to always review the full PR diff. |

### Instruction resolution order

1. If `prompt_file` is non-empty → read from your repo at `${GITHUB_WORKSPACE}/${prompt_file}`; **fail** if the file does not exist.
2. Else if `prompt_style` is non-empty → read built-in file from the action at `.github/pr-review-prompts/${prompt_style}.txt`; **fail** if not one of `team` \| `technical` \| `users`.
3. Else → use the built-in legacy instruction text (similar to ProductDock).

After that, the action appends a short **format** paragraph (Markdown vs plain), then the diff content, in a single user message to the API.

### Incremental review behavior

When `incremental_review: true` (the default), each comment posted by the action contains a hidden HTML marker:

```
<!-- pr-reviewer-sha: <head-sha> -->
```

On the next push to the same PR, the action scans the comment history for this marker and uses the recorded SHA as the `git diff` base instead of the PR base branch. This means the model only sees what changed since the last review, keeping each comment focused and cost-efficient.

Fallback to a full diff happens automatically when:

- The PR has no previous review comment (first run, or comments were deleted).
- The recorded SHA is not reachable in the local git history (force push, interactive rebase).
- `incremental_review` is set to `false`.

## Built-in prompt styles

The action bundles three prompt styles (no setup required in your repo):

- **team** — Internal team summary (what changed, why, affected areas)
- **technical** — Technical review (code quality, patterns, edge cases)
- **users** — User-facing summary (features, UX impact)

Set `prompt_style: team` (or `technical` / `users`) to use them. To use your own prompts, set `prompt_file` with a path to a file in your repository.

## Differences from ProductDock

| Topic | ProductDock | JurojinPoker-PR-Reviewer |
|-------|-------------|---------------------------|
| Instructions | Single fixed English string | File, named style under a path, or legacy string |
| Missing prompt file | N/A | Explicit **failure** with a clear message when a configured file is missing |
| Output format | Plain summary (no Markdown) by instruction | **Markdown (GFM)** requested by default (`use_markdown: true`); set `false` for plain text |
| Script inputs | Positional arguments | **Environment variables** from the composite step (avoids fragile `run` line continuations) |

Very large diffs may exceed model context or produce truncated comments; consider smaller PRs or raising `MAX_TOKENS` within model limits.

## Licence

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
