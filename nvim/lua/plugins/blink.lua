-- blink.cmp: base spec from NvChad, plus a VS Code-style behaviour layer
return {
  { import = "nvchad.blink.lazyspec" },

  {
    "saghen/blink.cmp",
    -- opts is a table -> lazy deep-merges it on top of NvChad's blink config
    opts = {
      -- 1. Only run in real code buffers (no terminal / pickers / trees / cmdline)
      enabled = function()
        local blocked_buftype = {
          terminal = true,
          nofile = true,
          prompt = true,
          quickfix = true,
        }
        local blocked_filetype = {
          ["NvimTree"] = true,
          ["TelescopePrompt"] = true,
          ["nvcheatsheet"] = true,
          ["nvdash"] = true,
        }

        if blocked_buftype[vim.bo.buftype] or blocked_filetype[vim.bo.filetype] then
          return false
        end
        -- still honours `vim.b.completion = false` on a per-buffer basis
        return true
      end,

      -- No completion on the `:` command line either
      cmdline = { enabled = false },

      -- Tables and columns of the connected database (plugins/dadbod.lua)
      sources = {
        per_filetype = { sql = { "snippets", "dadbod", "buffer" } },
        providers = { dadbod = { name = "Dadbod", module = "vim_dadbod_completion.blink" } },
      },

      completion = {
        -- Ghost text is Copilot's (configs/lspconfig.lua), not the menu's
        ghost_text = { enabled = false },
        list = {
          selection = {
            -- VS Code: show the menu but never auto-highlight the first item
            preselect = false,
            -- don't insert text while cycling; only <CR> commits (SelectBehavior.Select)
            auto_insert = false,
          },
        },
        -- menu pops up automatically as you type (menu,menuone)
        menu = { auto_show = true },
        documentation = { auto_show = true },
      },

      keymap = {
        preset = "default",

        -- Ctrl+Space toggles the menu
        ["<C-space>"] = { "show", "show_documentation", "hide_documentation" },

        -- Only <CR> commits the highlighted item; falls back to a real newline
        -- when nothing is selected (confirm({ select = false }))
        ["<CR>"] = { "accept", "fallback" },

        -- Tab / Down cycle forward, Shift-Tab / Up cycle backward. With no
        -- menu or snippet, Tab indents and Shift-Tab outdents the current line
        -- (insert-mode <C-d>), as in VS Code.
        --
        -- Tab, in order: the next menu item once one is highlighted; the
        -- next snippet field; Copilot's next-edit suggestion (jump to it,
        -- then apply it); Copilot's ghost text; the menu's first item;
        -- indent. The menu opens with nothing highlighted, so ghost text wins
        -- until Down / Up picks an item.
        ["<Tab>"] = {
          function(cmp)
            if cmp.is_menu_visible() and cmp.get_selected_item() then
              return cmp.select_next()
            end
          end,
          "snippet_forward",
          function()
            return package.loaded.sidekick ~= nil and require("sidekick").nes_jump_or_apply()
          end,
          function()
            return vim.lsp.inline_completion.get()
          end,
          "select_next",
          "fallback",
        },
        ["<Down>"] = { "select_next", "fallback" },
        ["<S-Tab>"] = {
          "select_prev",
          "snippet_backward",
          function()
            -- "i": ahead of any typeahead, so it's still in Insert mode
            vim.api.nvim_feedkeys(vim.keycode "<C-d>", "ni", false)
            return true
          end,
        },
        ["<Up>"] = { "select_prev", "fallback" },
      },
    },
  },
}
