# Session Snapshot

## 0.1.1

- Adapted the settings panel text, controls, borders, and hover states to
  Omarchy popup theme tokens for readable contrast across themes.

`hancore.session-snapshot` adds a small Omarchy top-bar control for the
desktop session snapshot engine already shipped by the shell.

## Install

```sh
omarchy plugin add https://github.com/iamcheyan/omarchy-session-snapshot.git --enable
```

The plugin installs a top-bar widget and user-level systemd units for rolling
snapshots and save-on-session-end. It stores snapshot data under
`~/.local/state/omarchy-session-snapshot/` and does not require another
checkout at runtime.

Its menu follows the desktop state:

- when windows are open, show `Save snapshot` and `Save & clear desktop`;
- after `Save & clear desktop`, show `Restore snapshot` only while the desktop is empty;
- show whether a snapshot exists, how many windows it contains, and when it was saved;
- enable the default “save before logout, reboot, or shutdown” behavior;
- persist that preference at `~/.config/omarchy/session-save-on-exit`, which is
  also read by the shell power menu;
- preserve the existing automatic next-login restore marker and teardown-safe
  rolling snapshot logic.

This is a pseudo-hibernate feature. It restores launchable application windows,
workspaces, terminal directories, and detected tmux/zellij sessions. Kitty
windows are intentionally restored one-to-one: every saved Kitty OS window
keeps its own Kitty tabs/panes and its own Hyprland workspace/position. The
plugin never merges sibling Kitty windows. It does not
preserve process memory, unsaved buffers, or application-internal state.

The plugin contains its own session snapshot engine under `bin/` and does not
depend on another shell checkout. Snapshot data is kept under
`~/.local/state/omarchy-session-snapshot/session/`.

The plugin service installs user-level systemd links for a five-minute rolling
snapshot and a final save when the graphical session ends. On the next login,
the service consumes the restore marker and restores the saved session once.

## Remove

Disable the plugin before removing it so its user-level units are stopped:

```sh
omarchy plugin disable hancore.session-snapshot
omarchy plugin remove hancore.session-snapshot
```

Removing the plugin does not delete the saved snapshot state. Remove
`~/.local/state/omarchy-session-snapshot/` separately if you also want to clear
the saved session.

## Development

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" bar/widget.qml SnapshotPanel.qml
```
