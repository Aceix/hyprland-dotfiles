-- Indent guides and the current block, and the symbol under the cursor lit
-- up everywhere it's used. Otherwise a library: utils/git_host.lua uses
-- snacks.gitbrowse for the open / copy-link keys.
--
-- Colors are in chadrc.lua (SnacksIndent*, LspReference*), so they follow
-- the theme.
return {
  {
    "folke/snacks.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      indent = {
        enabled = true,
        -- The current block's guide slides in as the cursor moves between
        -- blocks, and is drawn as an outline (╭─ │ ╰─>) pointing at the
        -- block's first line; <leader>ub switches back to the plain guide
        -- (utils/block_outline.lua)
        animate = { duration = { step = 15, total = 250 } },
        chunk = {
          enabled = true,
          char = { corner_top = "╭", corner_bottom = "╰" },
        },
      },
      -- Like VS Code's "highlight occurrences": other uses of the symbol
      -- under the cursor, as found by the language server (documentHighlight).
      -- ]] / [[ jump between them (mappings.lua).
      words = { enabled = true, debounce = 150 },
    },
  },

  -- Replaced by snacks.indent above
  { "lukas-reineke/indent-blankline.nvim", enabled = false },
}
