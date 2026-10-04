#!/usr/bin/env bash
# Pi RPC contract test double.
# Reads JSON commands from stdin, writes deterministic JSON events/responses to stdout.

# Opt-in: report the physical working directory and PI_EX_STUB_REPORT, then continue.
if [ -n "$PI_EX_STUB_REPORT" ]; then
  jq -cn --arg cwd "$(pwd -P)" --arg env "$PI_EX_STUB_REPORT" \
    '{"type":"stub_report","cwd":$cwd,"env":$env}'
fi

while IFS= read -r line; do
  command=$(echo "$line" | jq -r '.type // ""')
  id=$(echo "$line" | jq -r '.id // ""')
  shell_command=$(echo "$line" | jq -r '.command // ""')
  provider=$(echo "$line" | jq -r '.provider // ""')
  model_id=$(echo "$line" | jq -r '.modelId // ""')

  case "$command" in
    prompt)
      echo '{"type":"agent_start"}'
      echo '{"type":"turn_start"}'
      echo '{"type":"message_start"}'
      echo '{"type":"message_update","assistantMessageEvent":{"type":"text_start"}}'
      echo '{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"Hello from contract pi"}}'
      echo '{"type":"message_update","assistantMessageEvent":{"type":"text_end"}}'
      echo '{"type":"message_update","assistantMessageEvent":{"type":"done","reason":"stop"}}'
      echo '{"type":"message_end"}'
      echo '{"type":"turn_end"}'
      echo '{"type":"agent_end","messages":[]}'
      ;;
    get_state)
      echo "{\"type\":\"response\",\"command\":\"get_state\",\"success\":true,\"id\":\"$id\",\"data\":{\"isStreaming\":false}}"
      ;;
    get_messages)
      echo "{\"type\":\"response\",\"command\":\"get_messages\",\"success\":true,\"id\":\"$id\",\"data\":{\"messages\":[{\"role\":\"assistant\",\"content\":\"Hello from contract history\"}]}}"
      ;;
    get_session_stats)
      echo "{\"type\":\"response\",\"command\":\"get_session_stats\",\"success\":true,\"id\":\"$id\",\"data\":{\"totals\":{\"inputTokens\":120,\"outputTokens\":40},\"cost\":{\"usd\":0.12}}}"
      ;;
    bash)
      echo "{\"type\":\"response\",\"command\":\"bash\",\"success\":true,\"id\":\"$id\",\"data\":{\"stdout\":\"hello\",\"stderr\":\"\",\"exitCode\":0,\"receivedCommand\":\"$shell_command\"}}"
      ;;
    set_model)
      echo "{\"type\":\"response\",\"command\":\"set_model\",\"success\":true,\"id\":\"$id\",\"data\":{\"provider\":\"$provider\",\"modelId\":\"$model_id\",\"applied\":true}}"
      ;;
    *)
      echo "{\"type\":\"response\",\"command\":\"$command\",\"success\":true,\"id\":\"$id\",\"data\":{}}"
      ;;
  esac
done

# Opt-in: keep the process alive after stdin closes so stop/2 observes a live child.
if [ -n "$PI_EX_STUB_LINGER" ]; then
  exec sleep "$PI_EX_STUB_LINGER"
fi
