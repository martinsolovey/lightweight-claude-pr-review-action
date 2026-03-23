# Long PR Issue: "Argument list too long" and null comment

## Problem

When a pull request has a very large diff, the action may post a comment with the literal text `"null"` instead of the actual review summary.

## Root cause

The script builds the full prompt (instructions + format suffix + diff content) and passes it to `jq` as a command-line argument:

```bash
messages_json=$(jq -n --arg body "$full_prompt" '[{"role": "user", "content": $body}]')
```

On Linux, there is a limit (`ARG_MAX`, typically ~2 MB) on the total size of command-line arguments. When the diff exceeds this limit, `jq` fails with:

```
/usr/bin/jq: Argument list too long
```

When this happens:

1. `messages_json` ends up empty or invalid
2. The request to the OpenAI API is malformed
3. OpenAI returns a response with `content: null` or an error
4. `extract_summary` yields the literal string `"null"`
5. The script posts `"null"` as the PR comment body

## Symptoms

- Workflow completes without explicit errors (the `jq` failure may appear in logs)
- PR comment shows: `null` (plus the hidden SHA marker)
- Log line: `Argument list too long` on the `jq` call in `call_openai_api` (around line 111 in `scripts/analyze-code.sh`)

## Affected code

- **File:** `scripts/analyze-code.sh`
- **Function:** `call_openai_api`
- **Line:** The `jq -n --arg body "$full_prompt"` invocation that builds the `messages` JSON for the API request

## Solution (implemented)

The script uses a file-based flow throughout to avoid ARG_MAX:

1. **`call_openai_api`** — Accepts `prompt_file` instead of the prompt string. Uses `jq --rawfile body "$prompt_file"` to read the prompt, writes the full request JSON to a temp file, and sends it with `curl -d @file`. Writes the API response to `response_file` instead of stdout.

2. **`extract_summary`** — Accepts `response_file` and reads from it (no large string passed as argument).

3. **`post_summary_to_github`** — Accepts `summary_file` instead of the summary string. Uses `jq --rawfile body "$summary_file"` and `curl -d @file` for the comment payload, covering the case of very long model outputs.

4. **`main`** — Uses temp files for prompt, response, and summary; never passes large strings as arguments.

## Related

- Linux `ARG_MAX`: usually 2,097,152 bytes on modern systems (`getconf ARG_MAX`)
- Consider documenting a recommended `MAX_TOKENS` or diff size guidance for users with very large PRs.
