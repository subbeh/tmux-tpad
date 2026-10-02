#!/usr/bin/env bash
set -eo pipefail

# Configuration
if [[ "$(tmux show-options -gqv @tpad-debug)" == "true" ]]; then
  LOG_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/tpad.log"
  exec &>>"$LOG_FILE"

  set -x
fi

readonly CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TPAD_SCRIPT="${CURRENT_DIR}/tpad.tmux"

declare -A DEFAULTS=(
  [title]="#[fg=magenta,bold] 󱂬 TPad: @instance@ "
  [dir]="$HOME"
  [width]="60%"
  [height]="60%"
  [style]="fg=blue"
  [border_style]="fg=cyan,rounded"
)

main() {
  check_dependencies
  case "${1:-}" in
  toggle) toggle_popup "$2" ;;
  fullscreen) toggle_fullscreen ;;
  eject) eject_pane ;;
  "") initialize_instances ;;
  *)
    show_help
    exit 1
    ;;
  esac
}

get_global_config() {
  local key="$1"
  local default="$2"
  local val="$(tmux show-option -gqv "@tpad-${key}")"
  echo "${val:-$default}"
}

initialize_instances() {
  local fullscreen_key="$(get_global_config bind-fullscreen C-f)"
  local eject_key="$(get_global_config bind-eject C-e)"
  tmux bind-key -N "TPad: Fullscreen" "$fullscreen_key" run-shell "$TPAD_SCRIPT fullscreen"
  tmux bind-key -N "TPad: Eject" "$eject_key" run-shell "$TPAD_SCRIPT eject"
  tmux show-options -g | sed -n 's/^@tpad-\([^-]*\)-bind .*/\1/p' | sort -u | while read -r instance; do
    bind_key "$instance"
  done
}

toggle_popup() {
  local instance="$1"
  local session="tpad_${instance}"
  local working_dir=""
  # Identifies the session (or per-dir window) for eject/reclaim tracking
  local target="$session"

  # Check if per-directory sessions/windows are enabled
  local per_dir="$(get_config "$instance" per-dir)"
  if [[ "$per_dir" == "true" || "$per_dir" == "window" ]]; then
    local pane_dir="$(tmux display-message -p '#{pane_current_path}')"
    local git_root="$(get_git_root "$pane_dir")"

    # Fall back to using pane's current directory if not in a git repo
    working_dir="${git_root:-$pane_dir}"
    target="tpad_${instance}_$(sanitize_dir_name "$working_dir")"
    # In window mode all directories share one session with a window per directory
    [[ "$per_dir" == "true" ]] && session="$target"
  fi

  local current_session="$(tmux display-message -p '#{session_name}')"

  if [[ "$current_session" == "$session" ]]; then
    if tmux show-env -g TPAD_ZOOMED | grep -q "$session"; then
      tmux setenv -g -u TPAD_ZOOMED
      tmux switch-client -t "$(tmux show-env -g TPAD_PARENT_SESSION | cut -d= -f2)"
    else
      tmux detach
    fi
  else
    if [[ "$current_session" =~ tpad_* ]]; then
      tmux detach
    fi
    tmux setenv -g TPAD_PARENT_SESSION "$current_session"
    if ! reclaim_ejected_pane "$instance" "$session" "$target" "$working_dir"; then
      create_session_if_needed "$instance" "$session" "$working_dir"
    fi
    if [[ "$per_dir" == "window" ]]; then
      select_dir_window "$instance" "$session" "$working_dir"
    fi
    local popup_opts=()
    while IFS= read -r opt; do
      popup_opts+=("$opt")
    done < <(build_popup_options "$instance" "$working_dir")

    tmux display-popup "${popup_opts[@]}" -E "tmux attach -t $session"
  fi
}

create_session_if_needed() {
  local instance="$1"
  local session="$2"
  local working_dir="$3"
  tmux has-session -t "$session" 2>/dev/null && return

  # Use provided working_dir or fall back to config
  local dir="${working_dir:-$(get_config "$instance" dir)}"
  local session_id="$(tmux new-session -dP -s "$session" -c "$dir" -F '#{session_id}')"
  if [[ "$(get_config "$instance" per-dir)" == "window" ]]; then
    tmux set -w -t "${session_id}:" @tpad-dir "$dir"
    tmux rename-window -t "${session_id}:" "$(basename "$dir")"
  fi
  configure_session "$instance" "$session_id"
}

configure_session() {
  local instance="$1"
  local session_id="$2"
  apply_session_config "$instance" "$session_id"
  run_cmd "$instance" "$session_id"
}

run_cmd() {
  local instance="$1"
  local target="$2"
  local cmd="$(get_config "$instance" cmd)"
  if [[ -n "$cmd" ]]; then
    local use_shell="$(get_config "$instance" shell)"
    if [[ "$use_shell" == "true" ]]; then
      tmux send-keys -t "$target" "$cmd" C-m
    else
      tmux send-keys -t "$target" "exec $cmd" C-m
    fi
  fi
}

# Window mode: select the session's window for dir, creating it if needed
select_dir_window() {
  local instance="$1"
  local session="$2"
  local dir="$3"
  local window_id="" id win_dir

  while IFS=$'\t' read -r id win_dir; do
    if [[ "$win_dir" == "$dir" ]]; then
      window_id="$id"
      break
    fi
  done < <(tmux list-windows -t "$session" -F $'#{window_id}\t#{@tpad-dir}')

  if [[ -z "$window_id" ]]; then
    window_id="$(tmux new-window -dP -t "${session}:" -c "$dir" -F '#{window_id}')"
    tmux set -w -t "$window_id" @tpad-dir "$dir"
    tmux rename-window -t "$window_id" "$(basename "$dir")"
    run_cmd "$instance" "$window_id"
  fi
  tmux select-window -t "$window_id"
}

apply_session_config() {
  local instance="$1"
  local session_id="$2"
  tmux set -t "$session_id" default-terminal "$TERM"
  tmux set -t "$session_id" key-table "tpad_$instance"
  tmux set -t "$session_id" status off
  tmux set -t "$session_id" detach-on-destroy on
  tmux set -t "$session_id" @tpad-instance "$instance"
  # Window mode: close the popup when a window exits instead of showing another directory's window
  if [[ "$(get_config "$instance" per-dir)" == "window" ]]; then
    tmux set-hook -t "$session_id" window-unlinked "detach-client -s '$session_id'"
  fi
  set_opts "$instance" "$session_id"

  local prefix="$(get_config "$instance" prefix)"
  if [[ -n "$prefix" ]]; then
    tmux set -t "$session_id" prefix "$prefix"
  fi
}

set_opts() {
  local instance="$1"
  local session_id="$2"
  local opts="$(get_config "$instance" opts)"
  [[ -z "$opts" ]] && return

  while IFS=';' read -r opt; do
    [[ -n "$opt" ]] && tmux set-option -t "$session_id" $opt
  done <<<"$opts"
}

get_config() {
  local instance="$1"
  local key="$2"
  local tmux_var="@tpad-${instance}-${key}"
  local val="$(tmux show-option -gqv "$tmux_var")"

  if [[ -z "$val" ]]; then
    val="${DEFAULTS[$key]/@instance@/${instance^}}"
  fi

  echo "$val"
}

bind_key() {
  local instance="$1"
  local key="$(get_config "$instance" bind)"
  [[ -z "$key" ]] && return

  local table="$(get_config "$instance" table)"

  # Mouse events always require the root table
  if [[ -z "$table" ]]; then
    case "$key" in
    Mouse* | DoubleClick* | TripleClick* | WheelUp* | WheelDown*) table="root" ;;
    esac
  fi

  if [[ -n "$table" ]]; then
    tmux bind-key -T "$table" -N "TPad: Toggle $instance" "$key" run-shell "$TPAD_SCRIPT toggle $instance"
  else
    tmux bind-key -N "TPad: Toggle $instance" "$key" run-shell "$TPAD_SCRIPT toggle $instance"
  fi

  local eject_key="$(get_global_config bind-eject C-e)"
  tmux bind-key -T "tpad_$instance" -N "TPad: Toggle $instance" "$key" run-shell "$TPAD_SCRIPT toggle $instance"
  tmux bind-key -T "tpad_$instance" -N "TPad: Eject" "$eject_key" run-shell "$TPAD_SCRIPT eject"
}

build_popup_options() {
  local instance="$1"
  local working_dir="$2"
  declare -A opt_map=(
    [T]="title"
    [S]="style"
    [s]="border_style"
    [b]="border_lines"
    [h]="height"
    [w]="width"
    [x]="pos_x"
    [y]="pos_y"
    [d]="dir"
    [e]="env"
  )

  for opt in "${!opt_map[@]}"; do
    local val=""
    # Use provided working_dir for the dir option if available
    if [[ "$opt" == "d" && -n "$working_dir" ]]; then
      val="$working_dir"
    elif [[ "$opt" == "T" && -n "$working_dir" && "$(get_config "$instance" per-dir)" != "window" ]]; then
      # Append directory name to title if per-dir sessions are enabled
      val="$(get_config "$instance" "${opt_map[$opt]}")"
      local dir_name="$(basename "$working_dir")"
      val="${val% } [${dir_name}]  "
    else
      val="$(get_config "$instance" "${opt_map[$opt]}")"
    fi
    if [[ -n "$val" ]]; then
      echo "-${opt}"
      echo "${val}"
    fi
  done
}

check_dependencies() {
  if ! command -v tmux &>/dev/null; then
    echo "Error: tmux is required but not installed" >&2
    exit 1
  fi
}

get_git_root() {
  local pane_dir="$1"
  if [[ -d "$pane_dir/.git" ]]; then
    echo "$pane_dir"
    return
  fi

  (cd "$pane_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || echo ""
}

sanitize_dir_name() {
  local dir="$1"
  # Get the basename and convert to safe session name suffix
  basename "$dir" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '_' | sed 's/_*$//'
}

toggle_fullscreen() {
  local current_session="$(tmux display-message -p '#{session_name}')"
  local parent_session="$(tmux show-env -g TPAD_PARENT_SESSION | cut -d= -f2)"
  local instance="$(tmux show-option -t "$current_session" -qv @tpad-instance)"

  if [[ "$current_session" =~ tpad_* ]]; then
    local zoomed_session="$(tmux show-env -g TPAD_ZOOMED | cut -d= -f2)"
    if [[ -n "$zoomed_session" ]]; then
      # Exiting fullscreen mode - clear fullscreen settings and restore config
      tmux setenv -g -u TPAD_ZOOMED
      tmux set -u -t "$current_session" status-left
      tmux set -u -t "$current_session" status-right
      tmux set -u -t "$current_session" status-justify
      tmux set -u -t "$current_session" status-position
      tmux set -u -t "$current_session" status-style
      apply_session_config "$instance" "$current_session"
      tmux switch-client -t "$parent_session"
      toggle_popup "$instance"
    else
      # Entering fullscreen mode
      tmux setenv -g TPAD_ZOOMED "$current_session"
      tmux detach
      tmux switch-client -t "$current_session"

      local title="$(get_config "$instance" title)"
      tmux set -t "$current_session" status on
      tmux set -t "$current_session" status-justify centre
      tmux set -t "$current_session" status-position top
      tmux set -t "$current_session" status-left ""
      tmux set -t "$current_session" status-right "${title} [FULLSCREEN]"
      tmux set -t "$current_session" status-style "bg=terminal,fg=terminal"
    fi
  fi
}

eject_pane() {
  local current_session="$(tmux display-message -p '#{session_name}')"
  if [[ ! "$current_session" =~ tpad_ ]]; then return; fi

  local parent_session="$(tmux show-env -g TPAD_PARENT_SESSION | cut -d= -f2)"
  if [[ -z "$parent_session" ]]; then return; fi

  local instance="$(tmux show-option -t "$current_session" -qv @tpad-instance)"
  local pane_id="$(tmux display-message -p '#{pane_id}')"

  local split_dir="$(get_config "$instance" eject-split)"
  local split_size="$(get_config "$instance" eject-size)"
  local join_opts=()
  case "$split_dir" in
  right) join_opts+=(-h) ;;
  left) join_opts+=(-h -b) ;;
  above) join_opts+=(-b) ;;
  *) ;;
  esac
  if [[ -n "$split_size" ]]; then
    join_opts+=(-l "${split_size}%")
  fi

  # Window mode: track the ejected pane per directory window, not per session
  local target="$current_session"
  local win_dir="$(tmux display-message -p '#{@tpad-dir}')"
  if [[ -n "$win_dir" ]]; then
    target="tpad_${instance}_$(sanitize_dir_name "$win_dir")"
  fi

  tmux join-pane "${join_opts[@]}" -s "$pane_id" -t "$parent_session"
  local env_key="TPAD_EJECTED_$(echo "$target" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]' '_')"
  tmux setenv -g "$env_key" "$pane_id"
  # Close the popup — detach-on-destroy won't fire if other windows remain
  tmux detach-client -s "$current_session" 2>/dev/null || true
}

reclaim_ejected_pane() {
  local instance="$1"
  local session="$2"
  local target="$3"
  local working_dir="$4"
  local per_dir="$(get_config "$instance" per-dir)"
  local env_key="TPAD_EJECTED_$(echo "$target" | tr '[:lower:]' '[:upper:]' | tr -c '[:alnum:]' '_')"
  local pane_id="$(tmux show-env -g "$env_key" 2>/dev/null | cut -d= -f2)"

  if [[ -z "$pane_id" ]]; then return 1; fi
  # Check the pane still exists
  if ! tmux display-message -t "$pane_id" -p "" 2>/dev/null; then
    tmux setenv -g -u "$env_key"
    return 1
  fi

  tmux setenv -g -u "$env_key"
  if [[ "$per_dir" == "window" ]] && tmux has-session -t "$session" 2>/dev/null; then
    # Window mode — move the pane back into its own window
    tmux break-pane -d -s "$pane_id" -t "${session}:"
  elif tmux has-session -t "$session" 2>/dev/null; then
    # Session still exists (had multiple windows) — add pane as a new window
    local new_win="$(tmux new-window -dP -t "${session}:" -F '#{pane_id}')"
    tmux join-pane -s "$pane_id" -t "${session}:"
    tmux kill-pane -t "$new_win"
  else
    # Session was destroyed — recreate it around the ejected pane
    local dir="$(tmux display-message -t "$pane_id" -p '#{pane_current_path}')"
    local session_id="$(tmux new-session -dP -s "$session" -c "$dir" -F '#{session_id}')"
    local placeholder="$(tmux display-message -t "${session_id}:" -p '#{pane_id}')"
    apply_session_config "$instance" "$session_id"
    tmux join-pane -s "$pane_id" -t "${session}:"
    tmux kill-pane -t "$placeholder"
  fi
  if [[ "$per_dir" == "window" ]]; then
    tmux set -w -t "$pane_id" @tpad-dir "$working_dir"
    tmux rename-window -t "$pane_id" "$(basename "$working_dir")"
  fi
}

show_help() {
  cat <<EOF
TPad - Tmux Popup Manager

Usage:
  tpad.tmux [command]

Commands:
  (no command)  Initialize all configured instances
  toggle        Toggle a popup instance
EOF
}

main "$@"
