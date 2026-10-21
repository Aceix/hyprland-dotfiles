return {
  defaults = {
    -- `fd`/`rg` only skip `.git` when `--hidden` is *not* passed, and our
    -- find_files mappings pass `hidden=true` (mappings.lua `<leader>ff`,
    -- `<leader><leader>`), which surfaces every loose ref/packed object in
    -- `.git/`. `file_ignore_patterns` is applied in pickers.lua on entry
    -- paths, so one rule covers find_files, live_grep and grep_string.
    --
    -- Both anchors are needed: `fd --hidden` emits paths relative to cwd, so
    -- a repo-root `.git/HEAD` comes back as `.git/HEAD` (no leading segment
    -- for the `^.*[/\\]` form to match) while a nested repo comes back as
    -- `sub/dir/.git/HEAD`.
    file_ignore_patterns = {
      "^%.git/",
      "[/\\]%.git/",
    },
  },
}
