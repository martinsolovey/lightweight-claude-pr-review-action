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

@test "resolve_instruction_text_prompt_style_team" {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "${tmpdir}/.github/pr-review-prompts"
  echo "STYLE_TEAM_UNIQUE" > "${tmpdir}/.github/pr-review-prompts/team.txt"
  export GITHUB_WORKSPACE="$tmpdir"
  export PROMPT_FILE=""
  export PROMPT_STYLE="team"
  export PROMPTS_BASE_PATH=".github/pr-review-prompts"
  run resolve_instruction_text
  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == *"STYLE_TEAM_UNIQUE"* ]] || fail "Unexpected output: $output"
  rm -rf "$tmpdir"
}

@test "resolve_instruction_text_prompt_style_file_missing" {
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "${tmpdir}/.github/pr-review-prompts"
  export GITHUB_WORKSPACE="$tmpdir"
  export PROMPT_FILE=""
  export PROMPT_STYLE="technical"
  export PROMPTS_BASE_PATH=".github/pr-review-prompts"
  run resolve_instruction_text
  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == *"prompt style file not found"* ]] || fail "Unexpected output: $output"
  rm -rf "$tmpdir"
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

  run call_openai_api "$openai_api_key" "$full_prompt" "$gpt_model" "$max_tokens"

  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == "$mock_response" ]] || fail "Expected output '$mock_response', got '$output'"
}

@test "call_openai_api_with_special_chars_in_prompt" {
  local full_prompt=$'Line1\nQuote " and newline\nSecond line'
  local mock_response='{"choices":[{"message":{"content":"ok"}}]}'

  function curl() {
    echo "$mock_response"
  }

  run call_openai_api "key" "$full_prompt" "gpt-4o-mini" "100"
  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
}

@test "call_openai_api_failure" {
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

  run call_openai_api "key" "prompt" "gpt-4o-mini" "500"

  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == "$mock_error_response" ]] || fail "Expected error body in output, got '$output'"
}

@test "extract_summary_success" {
  local mock_response='{
    "choices": [
      {
        "message": {
          "content": "Test response from OpenAI API"
        }
      }
    ]
  }'

  run extract_summary "$mock_response"

  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == "Test response from OpenAI API" ]] || fail "Expected output, got '$output'"
}

@test "post_summary_to_github_success" {
  local github_token="test-github-token"
  local repository="test/repo"
  local pr_number="123"
  local summary="Test summary for GitHub"

  function curl() {
    echo "Comment posted successfully"
  }

  run post_summary_to_github "$github_token" "$repository" "$pr_number" "$summary"

  [ "$status" -eq 0 ] || fail "Expected status 0, got $status"
  [[ "$output" == "Comment posted successfully" ]] || fail "Expected output 'Comment posted successfully', got '$output'"
}

@test "post_summary_to_github_failure" {
  local github_token="test-github-token"
  local repository="test/repo"
  local pr_number="123"
  local summary="Test summary for GitHub"

  function curl() {
    echo "Error posting comment to GitHub"
    return 1
  }

  run post_summary_to_github "$github_token" "$repository" "$pr_number" "$summary"

  [ "$status" -eq 1 ] || fail "Expected status 1, got $status"
  [[ "$output" == "Error posting comment to GitHub" ]] || fail "Expected output, got '$output'"
}
