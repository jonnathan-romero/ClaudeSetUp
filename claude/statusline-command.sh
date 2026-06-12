#!/usr/bin/env bash
# Claude Code status line: [user@host dir] model  ctx: used/total (pct%)
# Reads the status-line JSON payload on stdin (see Claude Code statusLine docs).
input=$(cat)

mapfile -t arr < <(echo "$input" | jq -r '
  def fmt: if . >= 1000000 then "\(./1000000|floor)M" elif . >= 1000 then "\(./1000|floor)K" else tostring end;
  (.workspace.current_dir // .cwd),
  (.model.display_name // ""),
  ((.context_window.current_usage // {}) as $u
    | (($u.input_tokens // 0) + ($u.cache_creation_input_tokens // 0) + ($u.cache_read_input_tokens // 0)) | fmt),
  ((.context_window.context_window_size // 0) | fmt),
  (.context_window.used_percentage // 0 | floor | tostring)
')

cwd="${arr[0]}"
model="${arr[1]}"
used_t="${arr[2]}"
total_t="${arr[3]}"
pct="${arr[4]}"
name=$(basename "$cwd")

printf '\033[1;32m[%s@%s %s]\033[0m' "$(whoami)" "$(hostname -s)" "$name"
[ -n "$model" ] && printf ' \033[0;36m%s\033[0m' "$model"
[ "$total_t" != "0" ] && printf ' \033[0;33mctx: %s/%s (%s%%)\033[0m' "$used_t" "$total_t" "$pct"
