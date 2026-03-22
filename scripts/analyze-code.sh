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
# 1) PROMPT_FILE -> read file under GITHUB_WORKSPACE
# 2) PROMPT_STYLE + PROMPTS_BASE_PATH -> read {base}/{style}.txt
# 3) LEGACY_INSTRUCTION_TEXT
resolve_instruction_text() {
  local workspace="${GITHUB_WORKSPACE:-.}"
  workspace="${workspace%/}"

  local prompt_file="${PROMPT_FILE:-}"
  local prompt_style="${PROMPT_STYLE:-}"
  local base_path="${PROMPTS_BASE_PATH:-.github/pr-review-prompts}"
  base_path="${base_path%/}"

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
    local full_path="${workspace}/${base_path}/${prompt_style}.txt"
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

# Function to send the prompt to OpenAI API and get the response
call_openai_api() {
  local openai_api_key="$1"
  local full_prompt="$2"
  local gpt_model="$3"
  local max_tokens="$4"

  local messages_json
  messages_json=$(jq -n --arg body "$full_prompt" '[{"role": "user", "content": $body}]')

  curl -s -X POST "https://api.openai.com/v1/chat/completions" \
    -H "Authorization: Bearer $openai_api_key" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$gpt_model\", \"messages\": $messages_json, \"max_tokens\": $max_tokens}"
}

# Function to extract the summary from the OpenAI API response
extract_summary() {
  local response="$1"

  echo "$response" | jq -r '.choices[0].message.content'
}

# Function to post the summary as a comment on the pull request
post_summary_to_github() {
  local github_token="$1"
  local repository="$2"
  local pr_number="$3"
  local summary="$4"

  local comment_body
  comment_body=$(jq -n --arg body "$summary" '{body: $body}')

  curl -s -X POST \
    -H "Authorization: Bearer $github_token" \
    -H "Content-Type: application/json" \
    -d "$comment_body" \
    "https://api.github.com/repos/$repository/issues/$pr_number/comments"
}

# Main execution flow (reads from environment only)
main() {
  validate_required_env

  local instruction_text
  instruction_text=$(resolve_instruction_text)

  local use_md="${USE_MARKDOWN:-true}"
  local FULL_PROMPT
  FULL_PROMPT=$(prepare_prompt "$DIFF_FILE_PATH" "$instruction_text" "$use_md")

  local RESPONSE
  RESPONSE=$(call_openai_api "$OPENAI_API_KEY" "$FULL_PROMPT" "$GPT_MODEL" "$MAX_TOKENS")

  local SUMMARY
  SUMMARY=$(extract_summary "$RESPONSE")

  post_summary_to_github "$GITHUB_TOKEN" "$REPOSITORY" "$PR_NUMBER" "$SUMMARY"
}

# Execute the script (need this condition to prevent running the script when sourced in bats tests)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
