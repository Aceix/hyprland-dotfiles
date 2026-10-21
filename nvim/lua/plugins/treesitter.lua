return {
  "nvim-treesitter/nvim-treesitter",
  lazy = false,
  build = ":TSUpdate",
  -- still exposed as `opts` so NvChad's :TSInstallAll can read ensure_installed
  -- off the lazy spec
  opts = require "configs.treesitter",

  config = function(_, opts)
    local ts = require "nvim-treesitter"
    ts.setup {} -- `main` only accepts { install_dir }

    -- `main` dropped auto_install, so nothing acts on ensure_installed by
    -- itself. Build whatever is declared but missing; a no-op once they are all
    -- present, and asynchronous when they are not, so startup is not blocked.
    local installed = ts.get_installed "parsers"
    local need, seen = {}, {}

    for _, lang in ipairs(opts.ensure_installed or {}) do
      -- resolve filetype aliases onto the parser that actually backs them --
      -- `jsonc` is served by `json`, and asking for it by name never succeeds
      local parser = vim.treesitter.language.get_lang(lang) or lang
      if not seen[parser] and not vim.tbl_contains(installed, parser) then
        seen[parser] = true
        need[#need + 1] = parser
      end
    end

    if #need == 0 then
      return
    end

    vim.notify(
      ("[treesitter] building %d missing parser(s): %s"):format(#need, table.concat(need, ", ")),
      vim.log.levels.INFO
    )
    -- needs the `tree-sitter` CLI on $PATH; it reports its own errors via :TSLog
    ts.install(need)
  end,
}
