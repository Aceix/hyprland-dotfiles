return {
  -- Don't auto-chdir on every buffer: with `lsp` detection + a `package.json`
  -- pattern, opening a monorepo subpackage would re-root the global cwd there,
  -- and nvim-tree follows it (NvChad defaults `sync_root_with_cwd = true`).
  -- Root detection now only runs on an explicit `:ProjectRoot`.
  -- Note: the recent-projects history (utils/project_picker.lua) is only
  -- written on a chdir, so in manual mode it grows only when `:ProjectRoot` runs.
  manual_mode = true,

  -- Detect the project root by nearest LSP root, falling back to pattern matching
  detection_methods = { "lsp", "pattern" },
  patterns = {
    ".git",
    "_darcs",
    ".hg",
    ".bzr",
    ".svn",
    "Makefile",
    "package.json",
    "go.mod",
    "pubspec.yaml",
    "Cargo.toml",
  },
  ignore_lsp = {},
  exclude_dirs = {},
  show_hidden = false,
  -- Print each root change so it's visible which file/pattern triggered it
  -- rather than the cwd moving under you silently.
  silent_chdir = false,
  scope_chdir = "global",
  datapath = vim.fn.stdpath "data",
}
