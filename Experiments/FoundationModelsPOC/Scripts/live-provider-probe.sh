#!/bin/zsh
set -euo pipefail

provider=${1:-}
case "$provider" in
  deepseek|google|anthropic) ;;
  *)
    echo "Usage: $0 <deepseek|google|anthropic>" >&2
    exit 2
    ;;
esac

script_dir=${0:A:h}
repo_root=${script_dir:h:h:h}
env_file="$repo_root/.env"
if [[ ! -f "$env_file" ]]; then
  primary_root=$(git -C "$repo_root" worktree list --porcelain | awk '/^worktree / {sub(/^worktree /, ""); print; exit}')
  env_file="$primary_root/.env"
fi
if [[ ! -f "$env_file" ]]; then
  echo "Missing .env in this worktree and the primary checkout" >&2
  exit 2
fi
source "$env_file"

probe_dir=$(mktemp -d "/private/tmp/work-agent-$provider.XXXXXX")
trap 'rm -rf -- "$probe_dir"' EXIT

openai_tool=$(jq -n '{type:"function",function:{name:"read_fixture",description:"Read a committed fixture",parameters:{type:"object",properties:{path:{type:"string"}},required:["path"],additionalProperties:false}}}')
anthropic_tool=$(jq -n '{name:"read_fixture",description:"Read a committed fixture",input_schema:{type:"object",properties:{path:{type:"string"}},required:["path"],additionalProperties:false}}')
prompt='Work carefully. Determine whether a claimed answer can be trusted, but you must call read_fixture with path answer.txt as evidence before answering.'
tool_result='The fixture answer is 42.'

probe_openai_compatible() {
  local model=$1
  local endpoint=$2
  local key=$3
  local signature_query=$4
  local first_body first_code second_body second_code

  first_body=$(jq -n --arg model "$model" --arg prompt "$prompt" --argjson tool "$openai_tool" '{model:$model,messages:[{role:"user",content:$prompt}],tools:[$tool],stream:false}')
  first_code=$(curl -sS -o "$probe_dir/first.json" -w '%{http_code}' "$endpoint" -H "Authorization: Bearer $key" -H 'Content-Type: application/json' --data "$first_body")
  second_body=$(jq -n --arg model "$model" --arg prompt "$prompt" --arg result "$tool_result" --argjson tool "$openai_tool" --slurpfile first "$probe_dir/first.json" '{model:$model,messages:[{role:"user",content:$prompt},$first[0].choices[0].message,{role:"tool",tool_call_id:$first[0].choices[0].message.tool_calls[0].id,content:$result}],tools:[$tool],stream:false}')
  second_code=$(curl -sS -o "$probe_dir/second.json" -w '%{http_code}' "$endpoint" -H "Authorization: Bearer $key" -H 'Content-Type: application/json' --data "$second_body")

  jq -n --arg provider "$provider" --arg first_code "$first_code" --arg second_code "$second_code" --arg signature_query "$signature_query" --slurpfile first "$probe_dir/first.json" --slurpfile second "$probe_dir/second.json" '{provider:$provider,firstHTTP:($first_code|tonumber),emittedToolCall:($first[0].choices[0].message.tool_calls[0].function.name == "read_fixture"),providerStatePresent:(if $signature_query == "deepseek" then (($first[0].choices[0].message.reasoning_content // "")|length > 0) else (([$first[0].choices[0].message.extra_content.google.thought_signature,$first[0].choices[0].message.tool_calls[0].extra_content.google.thought_signature]|map(select(. != null))|length) > 0) end),secondHTTP:($second_code|tonumber),finalResponsePresent:(($second[0].choices[0].message.content // "")|length > 0),error:($second[0].error.message // $first[0].error.message // null)}'
}

probe_anthropic() {
  local first_body first_code second_body second_code
  first_body=$(jq -n --arg prompt "$prompt" --argjson tool "$anthropic_tool" '{model:"claude-sonnet-5",max_tokens:4096,thinking:{type:"adaptive"},output_config:{effort:"max"},messages:[{role:"user",content:$prompt}],tools:[$tool],stream:false}')
  first_code=$(curl -sS -o "$probe_dir/first.json" -w '%{http_code}' https://api.anthropic.com/v1/messages -H "x-api-key: $ANTHROPIC_API_KEY" -H 'anthropic-version: 2023-06-01' -H 'Content-Type: application/json' --data "$first_body")
  if [[ "$first_code" != 200 ]]; then
    jq -n --arg code "$first_code" --slurpfile first "$probe_dir/first.json" '{provider:"anthropic",firstHTTP:($code|tonumber),error:($first[0].error.message // null)}'
    return 1
  fi
  second_body=$(jq -n --arg prompt "$prompt" --arg result "$tool_result" --argjson tool "$anthropic_tool" --slurpfile first "$probe_dir/first.json" '{model:"claude-sonnet-5",max_tokens:4096,thinking:{type:"adaptive"},output_config:{effort:"max"},messages:[{role:"user",content:$prompt},{role:"assistant",content:$first[0].content},{role:"user",content:[{type:"tool_result",tool_use_id:($first[0].content[]|select(.type=="tool_use")|.id),content:$result}]}],tools:[$tool],stream:false}')
  second_code=$(curl -sS -o "$probe_dir/second.json" -w '%{http_code}' https://api.anthropic.com/v1/messages -H "x-api-key: $ANTHROPIC_API_KEY" -H 'anthropic-version: 2023-06-01' -H 'Content-Type: application/json' --data "$second_body")
  jq -n --arg first_code "$first_code" --arg second_code "$second_code" --slurpfile first "$probe_dir/first.json" --slurpfile second "$probe_dir/second.json" '{provider:"anthropic",firstHTTP:($first_code|tonumber),emittedToolCall:([$first[0].content[]?|select(.type=="tool_use" and .name=="read_fixture")]|length > 0),providerStatePresent:([$first[0].content[]?|select(.type=="thinking")|select((.signature|type)=="string" and (.signature|length)>0)]|length > 0),secondHTTP:($second_code|tonumber),finalResponsePresent:([$second[0].content[]?|select(.type=="text" and ((.text // "")|length > 0))]|length > 0),error:($second[0].error.message // null)}'
}

case "$provider" in
  deepseek)
    : "${DEEPSEEK_API_KEY:?DEEPSEEK_API_KEY is not assigned in .env}"
    probe_openai_compatible deepseek-v4-pro https://api.deepseek.com/chat/completions "$DEEPSEEK_API_KEY" deepseek
    ;;
  google)
    : "${GOOGLE_API_KEY:?GOOGLE_API_KEY is not assigned in .env}"
    probe_openai_compatible gemini-3.5-flash https://generativelanguage.googleapis.com/v1beta/openai/chat/completions "$GOOGLE_API_KEY" google
    ;;
  anthropic)
    : "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is not assigned in .env}"
    probe_anthropic
    ;;
esac
