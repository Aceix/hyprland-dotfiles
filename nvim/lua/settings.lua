-- Personal feature flags. Restart Neovim after changing one.
return {
  -- true: VS Code shortcuts (lua/vscode_keys.lua), multi-cursor
  -- (plugins/multicursor.lua) and the key reshuffles they need in neoscroll and
  -- dap. false: plain Vim/NvChad keys only. kitty's side of this lives in
  -- ~/.config/kitty/vscode-keys.conf (comment its `include` out to undo).
  vscode_keys = true,

  -- true: fetch the current repo in the background every 3 minutes, like
  -- VS Code's git.autofetch (lua/utils/git_autofetch.lua).
  git_autofetch = true,
}
