-- Indent guides and the current block, and the symbol under the cursor lit
-- up everywhere it's used; vim.ui.input / vim.ui.select as floating windows;
-- scratch buffers (<leader>. in mappings.lua); the <leader>u toggles
-- (utils/toggle.lua). Otherwise a library: utils/git_host.lua uses
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
      -- Input boxes open in the middle of the screen, like the pickers and
      -- menus (see config below for the one exception)
      input = { enabled = true },
      styles = { input = { row = 0.4 } },
      -- vim.ui.select only; Telescope stays the picker for everything else
      picker = { enabled = true, ui_select = true },
    },
    config = function(_, opts)
      require("snacks").setup(opts)
      -- LSP rename stays at the symbol, like VS Code's inline rename: Neovim
      -- marks that prompt with scope = "cursor". Snacks installs its
      -- vim.ui.input on UIEnter, so wrap it after that.
      vim.api.nvim_create_autocmd("UIEnter", {
        once = true,
        callback = vim.schedule_wrap(function()
          local input = vim.ui.input
          vim.ui.input = function(o, on_confirm)
            if o and o.scope == "cursor" then
              o = vim.tbl_extend("force", o, { win = { relative = "cursor", row = -3, col = 0, title_pos = "left" } })
            end
            return input(o, on_confirm)
          end
        end),
      })
    end,
  },

  -- Replaced by snacks.indent above
  { "lukas-reineke/indent-blankline.nvim", enabled = false },
}
