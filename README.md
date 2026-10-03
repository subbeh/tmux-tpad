# tmux-tpad

A lightweight floating window manager for tmux that allows you to create customizable popup sessions for different workflows.

![tpad](https://github.com/user-attachments/assets/b2c0e701-e9dd-45a8-9849-ae6328a6f933)

## Features

- Create multiple named popup sessions with different configurations
- Customize appearance, size, and position of each popup
- Run specific commands automatically when opening a popup
- Set custom working directories per popup
- Support for custom key bindings and tmux prefix keys
- Per-directory sessions or windows: create separate sessions (or windows) for each git repository
- Eject a pane from the popup into the parent session, and reclaim it back

## Installation

### Using TPM (recommended)

1. Install [Tmux Plugin Manager (TPM)](https://github.com/tmux-plugins/tpm) if you haven't already
1. Add the following to your `~/.tmux.conf`:
   ```tmux
   set -g @plugin 'Subbeh/tmux-tpad'
   ```
1. Press `prefix` + <kbd>I</kbd> to install the plugin

## Configuration

TPad sessions are configured using tmux options in the format: `@tpad-<session_name>-<option>`.

### Global Options

| Option | Default | Description |
| --------------------- | ------- | ------------------------------------------------- |
| @tpad-debug | false | Enable debug logging to `~/.cache/tpad.log` |
| @tpad-bind-fullscreen | C-f | Key to toggle fullscreen mode (prefix + key) |
| @tpad-bind-eject | C-e | Key to eject a pane from the popup (prefix + key) |

### Required Options

| Option | Description |
| ------ | ---------------------------------------------------------------- |
| bind | Key binding to toggle the popup session (e.g., "C-p" for Ctrl+P) |

### Appearance Options

| Option | Default | Description |
| ------------ | ---------------------------------------- | -------------------------------------------------------------- |
| title | `#[fg=terminal,bold] 󱂬 TPad: @instance@ ` | Popup window title |
| width | 60% | Popup width (percentage or columns) |
| height | 60% | Popup height (percentage or rows) |
| style | fg=blue | Popup window style |
| border_style | | Border style (e.g., "fg=cyan") |
| border_lines | rounded | Border line style (rounded/none/etc) |
| pos_x | | Horizontal position (percentage, pixels, or left/center/right) |
| pos_y | | Vertical position (percentage, pixels, or top/center/bottom) |

### Behavior Options

| Option | Default | Description |
| ----------- | ------- | ---------------------------------------------------------------------------- |
| cmd | | Command to execute when popup opens (runs with `exec` by default) |
| dir | $HOME | Working directory for the session |
| env | | Additional environment variables |
| opts | | Session-specific tmux options (semicolon-separated) |
| per-dir | false | `true`: a session per git repository/directory; `window`: a window per git repository/directory in one session |
| prefix | | Custom tmux prefix for the session |
| shell | false | Keep the shell process (for compound commands like `cmd1 && cmd2`) |
| table | | Key table for the binding (e.g., `root`). Auto-detected for mouse events. |
| eject-split | | Where to place the ejected pane: `right`, `left`, `above`, `below` (default) |
| eject-size | | Size of the ejected pane as a percentage (e.g. `30`) |

## Example Configuration

Here's a comprehensive example showing different use cases:

```tmux
# Simple scratchpad
set -g @tpad-scratchpad-bind    "C-p"
set -g @tpad-scratchpad-opts    "status on"
set -g @tpad-scratchpad-dir     "#{pane_current_path}"

# Git management with lazygit (separate session per git repo)
set -g @tpad-git-bind           "C-g"
set -g @tpad-git-cmd            "git rev-parse --is-inside-work-tree && exec lazygit"
set -g @tpad-git-per-dir        "true"
set -g @tpad-git-shell          "true"
set -g @tpad-git-style          "fg=red"

# Claude sessions (separate session per git repo)
set -g @tpad-claude-bind        "C-c"
set -g @tpad-claude-height      "90%"
set -g @tpad-claude-width       "30%"
set -g @tpad-claude-pos_x       "350%"
set -g @tpad-claude-pos_y       "80%"
set -g @tpad-claude-per-dir     "true"
set -g @tpad-claude-cmd         "claude-runner"
set -g @tpad-claude-opts        "status on"
set -g @tpad-claude-eject-split "right"
set -g @tpad-claude-eject-size  "40"

# Notes with Neovim
set -g @tpad-notes-bind         "C-n"
set -g @tpad-notes-dir          "${NOTES_DIR}"
set -g @tpad-notes-cmd          "nvim -c NvimTreeOpen"
set -g @tpad-notes-prefix       "None"
set -g @tpad-notes-width        "80%"
set -g @tpad-notes-height       "80%"

# K9s
set -g @tpad-k9s-bind           "C-k"
set -g @tpad-k9s-style          "fg=blue"
set -g @tpad-k9s-height         "80%"
set -g @tpad-k9s-width          "80%"
set -g @tpad-k9s-cmd            "k9s"

# Task management
set -g @tpad-tasks-bind         "C-t"
set -g @tpad-tasks-style        "fg=green"
set -g @tpad-tasks-height       "40%"
set -g @tpad-tasks-width        "40%"
set -g @tpad-tasks-pos_x        "right"
set -g @tpad-tasks-pos_y        "bottom"
set -g @tpad-tasks-cmd          "taskwarrior-tui"

# Right-click to open a scratchpad (table auto-detected as root for mouse events)
set -g @tpad-scratch-bind       "MouseDown3Pane"

# Keyboard shortcut without prefix key (explicit root table)
set -g @tpad-quick-bind         "C-Space"
set -g @tpad-quick-table        "root"
```

## Usage

1. Configure your popup sessions in `tmux.conf` as shown above
1. Press your tmux prefix key (default: <kbd>Ctrl</kbd>+<kbd>b</kbd>), then press the configured key binding to toggle the popup (e.g., <kbd>Ctrl</kbd>+<kbd>g</kbd> for the git session)
1. For root-table bindings (`table "root"` or mouse events), no prefix key is needed
1. The popup will close automatically when the command exits

### Full-screen mode

Full-screen mode can be toggled by pressing the tmux prefix key with <kbd>Ctrl</kbd>+<kbd>f</kbd> from within a tpad session (configurable via `@tpad-bind-fullscreen`).

### Eject & reclaim

A pane can be ejected from the popup into the parent session by pressing <kbd>prefix</kbd>+<kbd>Ctrl</kbd>+<kbd>e</kbd> from within a tpad session (configurable via `@tpad-bind-eject`). The popup closes and the pane is moved into the parent session as a split, with position and size controlled by `eject-split` and `eject-size`.

To reclaim the pane back into the popup, simply toggle the popup again with its normal key binding. If the ejected pane still exists it will be moved back into the tpad session (as a new window if the session has other windows); otherwise a fresh session is created as usual.

```tmux
# Eject to the right at 40% width, reclaim with C-c
set -g @tpad-claude-bind         "C-c"
set -g @tpad-claude-eject-split  "right"
set -g @tpad-claude-eject-size   "40"
```

### Per-Directory Sessions

When `per-dir` is enabled, tmux-tpad creates separate sessions for each git repository or directory. This is particularly useful for tools like lazygit, where you want independent sessions for different projects.

**How it works:**

- Detects the git root of your current pane's directory
- Creates a unique session per git root (e.g., `tpad_git_project1`, `tpad_git_project2`)
- Automatically sets the working directory to the git root
- Falls back to the current directory if not in a git repository

**Example:**

```tmux
set -g @tpad-git-bind "C-g"
set -g @tpad-git-cmd "lazygit"
set -g @tpad-git-per-dir "true"
```

Now pressing `Ctrl-g` in different git repositories will open separate lazygit sessions for each project.

**Windows instead of sessions:**

Set `per-dir` to `window` to keep a single `tpad_<instance>` session with one window per git root/directory. Toggling the popup selects (or creates) the window for the current directory. Windows are named after their directory, and the popup title omits the directory suffix. When a window's command exits, the popup closes rather than showing another directory's window.

```tmux
set -g @tpad-git-per-dir "window"
```

### Shell Mode

By default, commands run with `exec`, which replaces the shell process — no leftover shell when the command exits. For compound commands (using `&&`, `||`, or `;`), enable `shell` mode to keep the shell:

```tmux
# Compound command needs shell mode
set -g @tpad-git-cmd   "git rev-parse --is-inside-work-tree && exec lazygit"
set -g @tpad-git-shell "true"
```

The `exec` inside the command string is optional but recommended — it replaces the shell once the condition passes, so no extra process remains.

### Session-specific Options

You can set session-specific tmux options using the `opts` configuration. Multiple options can be separated with semicolons:

```tmux
# Enable the statusline for a specific popup
set -g @tpad-scratchpad-opts "status on"

# Multiple options
set -g @tpad-scratchpad-opts "status on; status-position top"
```

## Credits

This project was inspired by:

- [Dismissable Popup Shell in tmux](https://willhbr.net/2023/02/07/dismissable-popup-shell-in-tmux/)
- [omerxx/tmux-floax](https://github.com/omerxx/tmux-floax)

## License

MIT
