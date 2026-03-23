# How to implement the PR reviewer in your repository

Guide to add automated PR review with **OpenAI** to any GitHub repository via [JurojinPoker/jurojinpoker-pr-review-action](https://github.com/JurojinPoker/jurojinpoker-pr-review-action).

The workflow selects the prompt tone by **target branch** of the PR (`dev` → `technical`, `main` → `team`) with optional override via repository variable **`PR_REVIEW_STYLE`**.

---

## 1. What you get

- A comment on the PR when it's opened or updated (on `pull_request` events).
- Three built-in prompt styles: **`team`**, **`technical`**, **`users`** — no files to create in your repo.
- Automatic selection by **PR target branch**: `dev` → `technical`; `main` → `team` (configurable).
- Optional override: repository variable **`PR_REVIEW_STYLE`** (`team` | `technical` | `users`) to force a style regardless of branch.
- Custom prompts: use `prompt_file` to point to a file in your repo (takes precedence over `prompt_style`).

---

## 2. Prerequisites

- **GitHub** repository with permission to add workflows.
- Integration branches agreed (this guide assumes **`main`** and **`dev`**; adjust for `master`/`prod`/`staging` in §6).
- **OpenAI** account and secret **`OPENAI_API_KEY`** in the repo (or organization).

---

## 3. Minimal repo structure

```
.github/
  workflows/
    pr-summary-jurojin.yml
```

You do **not** need to create any prompt files unless you want a custom tone (§4.3).

---

## 4. Step by step

### 4.1 Secret

In **Settings → Secrets and variables → Actions**, create:

| Secret | Value |
|-------|-------|
| `OPENAI_API_KEY` | Your OpenAI API key |

### 4.2 Optional variable

| Variable | Use |
|----------|-----|
| `PR_REVIEW_STYLE` | If set, **overrides** the branch mapping and forces `team`, `technical`, or `users`. Only applies when not using `prompt_file`. |

### 4.3 Prompt: built-in vs custom

**Option A — Use built-in prompts (recommended to start)**

Do not create any files. The action uses `team.txt`, `technical.txt`, or `users.txt` internally based on `prompt_style`. The workflow in §4.4 configures this automatically.

**Option B — Use your own prompt**

1. Create the file in your repo, e.g. `.github/pr-review-prompts/custom.txt`.
2. In the workflow, add the `prompt_file` input pointing to that path and omit `prompt_style`:

```yaml
- name: Analyze Pull Request with OpenAI
  uses: JurojinPoker/jurojinpoker-pr-review-action@v1
  with:
    OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
    GITHUB_TOKEN: ${{ github.token }}
    REPOSITORY: ${{ github.repository }}
    PR_NUMBER: ${{ github.event.pull_request.number }}
    GPT_MODEL: gpt-4o-mini
    MAX_TOKENS: "1500"
    prompt_file: .github/pr-review-prompts/custom.txt   # overrides prompt_style
```

> `prompt_file` has **precedence** over `prompt_style`. If both are set, the file is used.

### 4.4 Workflow

Create `.github/workflows/pr-summary-jurojin.yml`:

```yaml
# OpenAI PR review via JurojinPoker/jurojinpoker-pr-review-action
# Built-in prompts: team | technical | users  (selected by branch or PR_REVIEW_STYLE)
# For custom prompt: add prompt_file and omit prompt_style (see docs)

name: PR Summary (Jurojin)

on:
  pull_request:
    branches: [main, dev]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  openai_pr_review:
    runs-on: ubuntu-latest
    name: Jurojin PR Review
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Select prompt style
        id: select_style
        env:
          BASE_REF: ${{ github.base_ref }}
          OVERRIDE_STYLE: ${{ vars.PR_REVIEW_STYLE }}
        run: |
          set -e
          if [ -n "$OVERRIDE_STYLE" ]; then
            STYLE="$OVERRIDE_STYLE"
          else
            case "$BASE_REF" in
              dev) STYLE=technical ;;
              main) STYLE=team ;;
              *) STYLE=team ;;
            esac
          fi
          echo "Using OpenAI prompt style: ${STYLE}"
          echo "prompt_style=${STYLE}" >> "$GITHUB_OUTPUT"

      - name: Analyze Pull Request with OpenAI
        uses: JurojinPoker/jurojinpoker-pr-review-action@v1
        with:
          OPENAI_API_KEY: ${{ secrets.OPENAI_API_KEY }}
          GITHUB_TOKEN: ${{ github.token }}
          REPOSITORY: ${{ github.repository }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
          GPT_MODEL: gpt-4o-mini
          MAX_TOKENS: "1500"
          prompt_style: ${{ steps.select_style.outputs.prompt_style }}
```

Check these two things before merging:

- `on.pull_request.branches`: list the target branches where you want the review to run.
- The `case "$BASE_REF"` block: branch names (`main`, `dev`) must **exactly** match your GitHub branch names.

### 4.5 Action version

The workflow uses `JurojinPoker/jurojinpoker-pr-review-action@v1`. You can pin a **SHA** instead of `@v1` for stricter security. For the latest changes during development, use `@main` (see [README](README.md) for versioning notes).

### 4.6 Deploy and test

1. Merge the workflow to your default branch.
2. Open a PR targeting `main` and another targeting `dev` (or the branches you configured).
3. In **Actions**, check the **PR Summary (Jurojin)** run; on the PR, verify the generated comment.

---

## 5. Permissions

```yaml
permissions:
  contents: read
  pull-requests: write
  issues: write
```

Comments are posted via the PR Issues API; the default `${{ github.token }}` is usually enough for the same repository.

---

## 6. Other branches (`master`, `prod`, `staging`)

If production or integration branches use different names, update **both** places in the workflow:

1. `pull_request.branches` (list of target branches that trigger the job).
2. The `case "$BASE_REF"` block (branch → `team` / `technical` / `users` mapping).

Example for `master` and `staging`:

```yaml
on:
  pull_request:
    branches: [master, staging]

# ... in the run block:
          case "$BASE_REF" in
            staging) STYLE=technical ;;
            master) STYLE=team ;;
            *) STYLE=team ;;
          esac
```

If you change only one, the workflow may not run or may pick the wrong prompt.

---

## 7. Parameters teams often change

| Parameter | Where | Notes |
|-----------|-------|-------|
| `GPT_MODEL` | `with:` of the action | Default `gpt-4o-mini`. |
| `MAX_TOKENS` | `with:` of the action | Increase (e.g. `2000`) if comments are cut off. |
| `prompt_file` | `with:` of the action | Path to a `.txt` file in the repo. Overrides `prompt_style`. |
| `prompt_style` | Output of previous step | `team` / `technical` / `users`. Ignored if `prompt_file` is set. |

---

## 8. Quick checklist

- [ ] `.github/workflows/pr-summary-jurojin.yml` with `on` and `case` aligned to your branches
- [ ] Secret `OPENAI_API_KEY`
- [ ] (Optional) Variable `PR_REVIEW_STYLE`
- [ ] (Optional) Custom prompt file if using `prompt_file`
- [ ] Test PR to each relevant target branch

---

## 9. Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `prompt style file not found` | Action version expects prompt files in your repo | Use action version with built-in prompts (v1+), or `@main` |
| `prompt_file not found` | `prompt_file` is set but the file does not exist in your repo | Create the file or remove `prompt_file` to use `prompt_style` |
| `Missing required environment variables` | Missing secrets/inputs | Ensure `OPENAI_API_KEY` and `GITHUB_TOKEN` are set |
| Re-run shows old behavior | GitHub caches workflows and actions | Push a new commit (e.g. `git commit --allow-empty -m "trigger" && git push`) to start a fresh run |
