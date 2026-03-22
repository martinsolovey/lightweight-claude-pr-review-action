# JurojinPoker-PR-Reviewer

GitHub Action that reviews pull requests using **OpenAI Chat Completions** (`/v1/chat/completions`). It reads the PR diff, sends instructions plus the diff to the model, and posts the reply as a **comment on the pull request** (issue comments API), same pattern as [ProductDock/openai-pr-review-action](https://github.com/productdock/openai-pr-review-action).

**You must run `actions/checkout` before this composite action** so instruction files (if you use `prompt_file` or `prompt_style`) exist under `GITHUB_WORKSPACE`. Without checkout, those paths are not available on the runner.

## Features

- Extracts the code diff between base and head SHAs (same as upstream).
- Resolves review instructions from a file, a named style under a base directory, or a built-in legacy prompt.
- Optional **GitHub Flavored Markdown** in the model output (default on), or plain text.
- Posts the summary as a PR comment.

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

### Explicit prompt file

```yaml
with:
  OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
  GITHUB_TOKEN: ${{ github.token }}
  REPOSITORY: ${{ github.repository }}
  PR_NUMBER: ${{ github.event.pull_request.number }}
  prompt_file: .github/pr-review-prompts/technical.txt
```

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
| `prompt_file` | no | *(empty)* | Path **relative to repo root** to the instruction file. Highest precedence. If set and missing, the job **fails**. |
| `prompt_style` | no | *(empty)* | One of `team`, `technical`, `users`. Resolves `{prompts_base_path}/{style}.txt`. Used only if `prompt_file` is empty. Invalid values fail the job. |
| `prompts_base_path` | no | `.github/pr-review-prompts` | Directory under the repo root for `prompt_style`. Trailing slashes are normalized. |
| `use_markdown` | no | `true` | If `true`, instructions ask for concise **GFM** (e.g. `##` headings, lists). If `false`, instructions ask for plain concise text. |

### Instruction resolution order

1. If `prompt_file` is non-empty → read `${GITHUB_WORKSPACE}/${prompt_file}`; **fail** if the file does not exist.
2. Else if `prompt_style` is non-empty → read `${GITHUB_WORKSPACE}/${prompts_base_path}/${prompt_style}.txt`; **fail** if not one of `team` \| `technical` \| `users`, or if the file does not exist.
3. Else → use the built-in legacy instruction text (similar to ProductDock).

After that, the action appends a short **format** paragraph (Markdown vs plain), then the diff content, in a single user message to the API.

## Sample prompts in this repository

This repo includes example files you can copy or adapt:

- [`.github/pr-review-prompts/team.txt`](.github/pr-review-prompts/team.txt)
- [`.github/pr-review-prompts/technical.txt`](.github/pr-review-prompts/technical.txt)
- [`.github/pr-review-prompts/users.txt`](.github/pr-review-prompts/users.txt)

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
