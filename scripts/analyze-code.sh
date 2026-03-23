#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# Legacy instruction text (ProductDock-style) when no prompt_file or prompt_style.
readonly LEGACY_INSTRUCTION_TEXT='Based on the code diff below, please provide a summary of the major insights derived. Also, check for any potential issues or improvements. The response should be a concise summary without any additional formatting, markdown, or characters outside the summary text.'

# Validate required environment variables (no positional args; secrets are not echoed).
validate_required_env() {
  if [[ -z "${OPENAI_API_KEY:-}" || -z "${GITHUB_TOKEN:-}" || -z "${REPOSITORY:-}" || \
        -z "${PR_NUMBER:-}" || -z "${DIFF_FILE_PATH:-}" || -z "${GPT_MODEL:-}" || \
        -z "${MAX_TOKENS:-}" ]]; then
    echo "Error: Missing required environment variables." >&2
    exit 1
  fi
}

# Resolve instruction text only (no diff, no format suffix). Precedence:
# 1) PROMPT_FILE -> read file from GITHUB_WORKSPACE (target repo, custom override)
# 2) PROMPT_STYLE -> read built-in file from ACTION_PATH (team, technical, users)
# 3) LEGACY_INSTRUCTION_TEXT
resolve_instruction_text() {
  local workspace="${GITHUB_WORKSPACE:-.}"
  workspace="${workspace%/}"
  local action_path="${ACTION_PATH:-}"

  local prompt_file="${PROMPT_FILE:-}"
  local prompt_style="${PROMPT_STYLE:-}"

  if [[ -n "$prompt_file" ]]; then
    local full_path="${workspace}/${prompt_file}"
    if [[ ! -f "$full_path" ]]; then
      echo "prompt_file not found: ${full_path}" >&2
      exit 1
    fi
    cat "$full_path"
    return 0
  fi

  if [[ -n "$prompt_style" ]]; then
    case "$prompt_style" in
      team|technical|users) ;;
      *)
        echo "Error: prompt_style must be one of: team, technical, users (got: ${prompt_style})" >&2
        exit 1
        ;;
    esac
    if [[ -z "$action_path" ]]; then
      echo "Error: ACTION_PATH is required when using prompt_style" >&2
      exit 1
    fi
    local full_path="${action_path}/.github/pr-review-prompts/${prompt_style}.txt"
    if [[ ! -f "$full_path" ]]; then
      echo "prompt style file not found: ${full_path}" >&2
      exit 1
    fi
    cat "$full_path"
    return 0
  fi

  printf '%s' "$LEGACY_INSTRUCTION_TEXT"
}

# Normalize use_markdown to true/false; default true when empty.
use_markdown_is_true() {
  local v="${1:-true}"
  v=$(echo "$v" | tr '[:upper:]' '[:lower:]')
  [[ "$v" == "true" ]]
}

# Build format suffix paragraph per spec (Spanish).
format_instruction_suffix() {
  local use_markdown="$1"
  if use_markdown_is_true "$use_markdown"; then
    printf '%s' "Responde en Markdown compatible con GitHub (GFM). Usa encabezados ## breves y listas cuando ayude; evita respuestas extremadamente largas."
  else
    printf '%s' "Responde en texto plano, sin Markdown; conciso."
  fi
}

# Prepare the full prompt: instructions + format suffix + diff content.
prepare_prompt() {
  local diff_file_path="$1"
  local instruction_text="$2"
  local use_markdown="${3:-true}"

  diff_file_path=$(echo "$diff_file_path" | xargs)

  if [[ ! -f "$diff_file_path" ]]; then
    echo "Error: Diff file not found at path: $diff_file_path" >&2
    exit 1
  fi

  local diff_content
  diff_content=$(cat "$diff_file_path")

  local format_suffix
  format_suffix=$(format_instruction_suffix "$use_markdown")

  echo -e "${instruction_text}\n\n${format_suffix}\n\n${diff_content}"
}

# Function to send the prompt to OpenAI API and get the response.
# Uses jq --rawfile and curl -d @file to avoid ARG_MAX when diff is large.
call_openai_api() {
  local openai_api_key="$1"
  local prompt_file="$2"
  local gpt_model="$3"
  local max_tokens="$4"
  local response_file="$5"

  local request_file
  request_file=$(mktemp)
  trap 'rm -f "$request_file"' RETURN

  jq -n \
    --rawfile body "$prompt_file" \
    --arg model "$gpt_model" \
    --argjson max_tokens "$max_tokens" \
    '{model: $model, messages: [{"role": "user", "content": $body}], max_tokens: $max_tokens}' \
    > "$request_file"

  curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Authorization: Bearer $openai_api_key" \
    -H "Content-Type: application/json" \
    -d @"$request_file" \
    > "$response_file"
}

# Function to extract the summary from the OpenAI API response file.
extract_summary() {
  local response_file="$1"

  jq -r '.choices[0].message.content' "$response_file"
}

# Function to post the summary as a comment on the pull request.
# Appends an invisible HTML marker with the reviewed HEAD SHA so incremental
# runs can find it and diff only from that point forward.
# Uses jq --rawfile and curl -d @file to avoid ARG_MAX when summary is large.
post_summary_to_github() {
  local github_token="$1"
  local repository="$2"
  local pr_number="$3"
  local summary_file="$4"
  local head_sha="${HEAD_SHA:-}"

  local marker=""
  if [[ -n "$head_sha" ]]; then
    marker=$'\n\n'"<!-- pr-reviewer-sha: ${head_sha} -->"
  fi

  local comment_file
  comment_file=$(mktemp)
  trap 'rm -f "$comment_file"' RETURN

  jq -n \
    --rawfile body "$summary_file" \
    --arg marker "$marker" \
    '{body: ($body + $marker)}' \
    > "$comment_file"

  curl -s -X POST \
    -H "Authorization: Bearer $github_token" \
    -H "Content-Type: application/json" \
    -d @"$comment_file" \
    "https://api.github.com/repos/$repository/issues/$pr_number/comments"
}

# Main execution flow (reads from environment only).
# Uses temp files throughout to avoid ARG_MAX with large diffs and summaries.
main() {
  validate_required_env

  local instruction_text
  instruction_text=$(resolve_instruction_text)

  local prompt_file response_file summary_file
  prompt_file=$(mktemp)
  response_file=$(mktemp)
  summary_file=$(mktemp)
  trap "rm -f '$prompt_file' '$response_file' '$summary_file'" EXIT

  local use_md="${USE_MARKDOWN:-true}"
  prepare_prompt "$DIFF_FILE_PATH" "$instruction_text" "$use_md" > "$prompt_file"

  call_openai_api "$OPENAI_API_KEY" "$prompt_file" "$GPT_MODEL" "$MAX_TOKENS" "$response_file"

  extract_summary "$response_file" > "$summary_file"

  post_summary_to_github "$GITHUB_TOKEN" "$REPOSITORY" "$PR_NUMBER" "$summary_file"
}

# Execute the script (need this condition to prevent running the script when sourced in bats tests)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
