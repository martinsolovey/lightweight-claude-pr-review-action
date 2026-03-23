#!/usr/bin/env bats

# Load Bats support for running commands and testing outputs
load 'libs/bats-support/load'
load 'libs/bats-assert/load'

# Source the script to make the functions available
source "./scripts/analyze-code.sh"

setup_env_valid() {
  export OPENAI_API_KEY="test-key"
  export GITHUB_TOKEN="test-token"
  export REPOSITORY="test/repo"
  export PR_NUMBER="123"
  export DIFF_FILE_PATH="tmp/pr_diff.txt"
  export GPT_MODEL="gpt-4o-mini"
  export MAX_TOKENS="500"
}

@test "validate_required_env_success" {
  setup_env_valid
  run validate_required_env
  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [ -z "$output" ] || fail "Expected no output, got '$output'"
}

@test "validate_required_env_failure" {
  setup_env_valid
  unset OPENAI_API_KEY
  run validate_required_env
  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == *"Missing required environment variables"* ]] || fail "Unexpected output: $output"
}

@test "resolve_instruction_text_legacy" {
  export PROMPT_FILE=""
  export PROMPT_STYLE=""
  run resolve_instruction_text
  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [ "$output" == "$LEGACY_INSTRUCTION_TEXT" ] || fail "Expected legacy text"
}

@test "resolve_instruction_text_prompt_file_success" {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo "Custom prompt body" > "${tmpdir}/custom.txt"
  export GITHUB_WORKSPACE="$tmpdir"
  export PROMPT_FILE="custom.txt"
  export PROMPT_STYLE=""
  run resolve_instruction_text
  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == *"Custom prompt body"* ]] || fail "Unexpected output: $output"
  rm -rf "$tmpdir"
}

@test "resolve_instruction_text_prompt_file_missing" {
  local tmpdir
  tmpdir=$(mktemp -d)
  export GITHUB_WORKSPACE="$tmpdir"
  export PROMPT_FILE="no/such/file.txt"
  export PROMPT_STYLE=""
  run resolve_instruction_text
  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == *"prompt_file not found"* ]] || fail "Unexpected output: $output"
  rm -rf "$tmpdir"
}

@test "resolve_instruction_text_prompt_style_invalid" {
  export PROMPT_FILE=""
  export PROMPT_STYLE="foo"
  run resolve_instruction_text
  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == *"prompt_style must be one of"* ]] || fail "Unexpected output: $output"
}

@test "resolve_instruction_text_prompt_style_missing_action_path" {
  export ACTION_PATH=""
  export PROMPT_FILE=""
  export PROMPT_STYLE="team"
  run resolve_instruction_text
  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == *"ACTION_PATH is required"* ]] || fail "Unexpected output: $output"
}

@test "resolve_instruction_text_prompt_style_team" {
  local action_dir
  action_dir=$(mktemp -d)
  mkdir -p "${action_dir}/.github/pr-review-prompts"
  echo "STYLE_TEAM_UNIQUE" > "${action_dir}/.github/pr-review-prompts/team.txt"
  export ACTION_PATH="$action_dir"
  export PROMPT_FILE=""
  export PROMPT_STYLE="team"
  run resolve_instruction_text
  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == *"STYLE_TEAM_UNIQUE"* ]] || fail "Unexpected output: $output"
  rm -rf "$action_dir"
}

@test "resolve_instruction_text_prompt_style_file_missing" {
  local action_dir
  action_dir=$(mktemp -d)
  mkdir -p "${action_dir}/.github/pr-review-prompts"
  export ACTION_PATH="$action_dir"
  export PROMPT_FILE=""
  export PROMPT_STYLE="technical"
  run resolve_instruction_text
  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == *"prompt style file not found"* ]] || fail "Unexpected output: $output"
  rm -rf "$action_dir"
}

@test "prepare_prompt_success_plain_suffix" {
  local diff_file_path="tmp/pr_diff.txt"
  mkdir -p "$(dirname "$diff_file_path")"
  echo "Mock diff content" > "$diff_file_path"

  local expected_output
  expected_output="${LEGACY_INSTRUCTION_TEXT}"$'\n\n'"Responde en texto plano, sin Markdown; conciso."$'\n\n'"Mock diff content"

  run prepare_prompt "$diff_file_path" "$LEGACY_INSTRUCTION_TEXT" "false"

  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == "$expected_output" ]] || fail "Expected output mismatch, got '$output'"

  rm -rf "$(dirname "$diff_file_path")"
}

@test "prepare_prompt_includes_gfm_suffix_when_markdown_true" {
  local diff_file_path="tmp/pr_diff.txt"
  mkdir -p "$(dirname "$diff_file_path")"
  echo "diff" > "$diff_file_path"

  run prepare_prompt "$diff_file_path" "Instructions only" "true"

  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == *"Markdown compatible con GitHub (GFM)"* ]] || fail "Expected GFM hint in output: $output"
  [[ "$output" != *"texto plano, sin Markdown"* ]] || fail "Did not expect plain-text suffix"

  rm -rf "$(dirname "$diff_file_path")"
}

@test "prepare_prompt_diff_missing" {
  run prepare_prompt "/nonexistent/diff.txt" "$LEGACY_INSTRUCTION_TEXT" "false"
  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == *"Diff file not found"* ]] || fail "Unexpected output: $output"
}

@test "call_openai_api_success" {
  local openai_api_key="test-api-key"
  local full_prompt="Test prompt for OpenAI API"
  local gpt_model="gpt-4o-mini"
  local max_tokens="500"

  local prompt_file response_file
  prompt_file=$(mktemp)
  response_file=$(mktemp)
  printf '%s' "$full_prompt" > "$prompt_file"
  trap "rm -f '$prompt_file' '$response_file'" EXIT

  local mock_response='{
    "choices": [
      {
        "message": {
          "content": "Test response from OpenAI API"
        }
      }
    ]
  }'

  function curl() {
    echo "$mock_response"
  }

  run call_openai_api "$openai_api_key" "$prompt_file" "$gpt_model" "$max_tokens" "$response_file"

  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [ -f "$response_file" ] || fail "Expected response to be written to file"
  [[ "$(cat "$response_file")" == *"Test response from OpenAI API"* ]] || fail "Expected mock response in file"
}

@test "call_openai_api_with_special_chars_in_prompt" {
  local full_prompt=$'Line1\nQuote " and newline\nSecond line'
  local prompt_file response_file
  prompt_file=$(mktemp)
  response_file=$(mktemp)
  printf '%s' "$full_prompt" > "$prompt_file"
  trap "rm -f '$prompt_file' '$response_file'" EXIT

  local mock_response='{"choices":[{"message":{"content":"ok"}}]}'

  function curl() {
    echo "$mock_response"
  }

  run call_openai_api "key" "$prompt_file" "gpt-4o-mini" "100" "$response_file"
  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$(cat "$response_file")" == *"ok"* ]] || fail "Expected mock response in file"
}

@test "call_openai_api_failure" {
  local prompt_file response_file
  prompt_file=$(mktemp)
  response_file=$(mktemp)
  echo "prompt" > "$prompt_file"
  trap "rm -f '$prompt_file' '$response_file'" EXIT

  local mock_error_response='{
    "error": {
      "message": "Invalid API key",
      "type": "authentication_error"
    }
  }'

  function curl() {
    echo "$mock_error_response"
    return 1
  }

  run call_openai_api "key" "$prompt_file" "gpt-4o-mini" "500" "$response_file"

  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [ -f "$response_file" ] || fail "Expected error body written to response file"
  [[ "$(cat "$response_file")" == *"Invalid API key"* ]] || fail "Expected error body in response file"
}

@test "call_openai_api_with_large_prompt" {
  # Create a prompt file > 100KB to ensure we avoid ARG_MAX (file-based flow)
  local prompt_file response_file
  prompt_file=$(mktemp)
  response_file=$(mktemp)
  trap "rm -f '$prompt_file' '$response_file'" EXIT

  # Generate ~150KB of content (would exceed ARG_MAX if passed as arg on some systems)
  local i
  for i in $(seq 1 1500); do
    printf '%100s' ' ' | tr ' ' 'x' >> "$prompt_file"
  done

  local mock_response='{"choices":[{"message":{"content":"ok"}}]}'
  function curl() {
    echo "$mock_response"
  }

  run call_openai_api "key" "$prompt_file" "gpt-4o-mini" "100" "$response_file"

  [ "$status" -eq 0 ] || fail "Expected status 0 with large prompt, got $status (possible ARG_MAX)"
  [[ "$output" != *"Argument list too long"* ]] || fail "Should not hit ARG_MAX with file-based flow"
  [[ "$(cat "$response_file")" == *"ok"* ]] || fail "Expected mock response in file"
}

@test "extract_summary_success" {
  local response_file
  response_file=$(mktemp)
  trap "rm -f '$response_file'" EXIT

  cat > "$response_file" << 'EOF'
{
  "choices": [
    {
      "message": {
        "content": "Test response from OpenAI API"
      }
    }
  ]
}
EOF

  run extract_summary "$response_file"

  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == "Test response from OpenAI API" ]] || fail "Expected output, got '$output'"
}

@test "post_summary_to_github_success" {
  local github_token="test-github-token"
  local repository="test/repo"
  local pr_number="123"
  local summary="Test summary for GitHub"

  local summary_file
  summary_file=$(mktemp)
  printf '%s' "$summary" > "$summary_file"
  trap "rm -f '$summary_file'" EXIT

  function curl() {
    echo "Comment posted successfully"
  }

  run post_summary_to_github "$github_token" "$repository" "$pr_number" "$summary_file"

  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == "Comment posted successfully" ]] || fail "Expected output 'Comment posted successfully', got '$output'"
}

@test "post_summary_to_github_failure" {
  local github_token="test-github-token"
  local repository="test/repo"
  local pr_number="123"
  local summary="Test summary for GitHub"

  local summary_file
  summary_file=$(mktemp)
  printf '%s' "$summary" > "$summary_file"
  trap "rm -f '$summary_file'" EXIT

  function curl() {
    echo "Error posting comment to GitHub"
    return 1
  }

  run post_summary_to_github "$github_token" "$repository" "$pr_number" "$summary_file"

  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == "Error posting comment to GitHub" ]] || fail "Expected output, got '$output'"
}
