-- The <leader>u on/off switches: { key, name, get, set, persist, default },
-- see utils/toggle.lua. `get` and a persisted `set` run at startup and every
-- time <leader>u opens, so neither may require() a lazy-loaded plugin.
local toggle = require "utils.toggle"

-- A loaded plugin's module, or nil: never loads it
local function loaded(mod)
  return package.loaded[mod]
end

return {
  {
    "h",
    "Inlay Hints (buffer)",
    get = function()
      return vim.lsp.inlay_hint.is_enabled { bufnr = 0 }
    end,
    set = function(on)
      vim.lsp.inlay_hint.enable(on, { bufnr = 0 })
    end,
  },
  {
    "s",
    "Secret Masking",
    get = function()
      local camouflage = loaded "camouflage"
      return camouflage == nil or camouflage.is_enabled()
    end,
    set = function(on)
      require("camouflage")[on and "enable" or "disable"]()
    end,
  },

  -- Formatting is manual (<leader>cf); this formats on every save instead
  {
    "F",
    "Format on Save",
    persist = true,
    default = false,
    get = function()
      return vim.g.format_on_save == true
    end,
    set = function(on)
      vim.g.format_on_save = on
      local group = vim.api.nvim_create_augroup("FormatOnSave", { clear = true })
      if on then
        vim.api.nvim_create_autocmd("BufWritePre", {
          group = group,
          callback = function(ev)
            if not vim.b[ev.buf].bigfile then
              require("conform").format { bufnr = ev.buf, lsp_format = "fallback", timeout_ms = 1500 }
            end
          end,
        })
      end
    end,
  },

  -- Error Lens-style messages (plugins/tiny-inline-diagnostic.lua); off =
  -- NvChad's plain virtual text
  {
    "d",
    "Inline Diagnostics",
    persist = true,
    default = true,
    get = function()
      return vim.g.inline_diagnostics ~= false
    end,
    set = function(on)
      vim.g.inline_diagnostics = on
      vim.diagnostic.config { virtual_text = not on and { prefix = "" } or false }
      local diag = loaded "tiny-inline-diagnostic"
      if diag then
        diag[on and "enable" or "disable"]()
      end
    end,
  },

  -- Reference counts, "run test", ... above declarations; <leader>cl runs one
  {
    "l",
    "Code Lens",
    persist = true,
    default = false,
    get = function()
      return vim.lsp.codelens.is_enabled()
    end,
    set = function(on)
      vim.lsp.codelens.enable(on)
    end,
  },

  -- Copilot (plugins/sidekick.lua, configs/lspconfig.lua)
  {
    "N",
    "Next Edit Suggestions",
    persist = true,
    default = true,
    get = function()
      return vim.g.sidekick_nes ~= false
    end,
    set = function(on)
      vim.g.sidekick_nes = on -- sidekick reads it before every request
      local nes = loaded "sidekick.nes"
      if nes and not on then
        nes.clear()
      end
    end,
  },
  {
    "g",
    "Ghost Text (inline completion)",
    persist = true,
    default = true,
    get = function()
      return vim.g.ghost_text ~= false
    end,
    set = function(on)
      vim.g.ghost_text = on -- read on LspAttach
      vim.lsp.inline_completion.enable(on)
    end,
  },

  -- Visual aids
  {
    "r",
    "Rainbow Brackets",
    persist = true,
    default = true,
    get = function()
      return vim.g.rainbow_brackets ~= false
    end,
    set = function(on)
      vim.g.rainbow_brackets = on -- new buffers (plugins/rainbow-delimiters.lua)
      local rainbow = loaded "rainbow-delimiters"
      if rainbow then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
            rainbow[on and "enable" or "disable"](buf)
          end
        end
      end
    end,
  },
  {
    "v",
    "CSV Table View",
    persist = true,
    default = true,
    get = function()
      return vim.g.csv_view ~= false
    end,
    set = function(on)
      vim.g.csv_view = on -- new buffers (plugins/csvview.lua)
      local csvview = loaded "csvview"
      if csvview then
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
          local ft = vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype
          if (ft == "csv" or ft == "tsv") and csvview.is_enabled(buf) ~= on then
            csvview[on and "enable" or "disable"](buf)
          end
        end
      end
    end,
  },
  -- Color swatches next to CSS / Tailwind colors (the language server's)
  {
    "C",
    "Color Swatches",
    persist = true,
    default = true,
    get = function()
      return vim.lsp.document_color.is_enabled()
    end,
    set = function(on)
      vim.lsp.document_color.enable(on)
    end,
  },
  -- Loads hardtime.nvim the first time it's switched on, and from then on at
  -- startup while it stays on
  {
    "H",
    "Habit Hints (hardtime)",
    persist = true,
    default = false,
    get = function()
      return vim.g.hardtime == true
    end,
    set = function(on)
      vim.g.hardtime = on
      local hardtime = loaded "hardtime"
      if hardtime then
        hardtime[on and "enable" or "disable"]()
      elseif on then
        -- Loading it is enough: its setup (deferred by the plugin) enables it
        -- from opts.enabled. Enabling now would map keys with its defaults,
        -- arrows disabled, before our options are merged in.
        require "hardtime"
      end
    end,
  },

  -- Spelling hints in code, comments and strings (typos-lsp); off by default
  {
    "S",
    "Spelling Suggestions",
    persist = true,
    default = false,
    get = function()
      return vim.lsp.is_enabled "typos_lsp"
    end,
    set = function(on)
      -- (on: attaches to the open buffers too; off: stops its clients)
      vim.lsp.enable("typos_lsp", on)
    end,
  },

  -- Off by default; while on, every file buffer opens it (autocmds.lua).
  -- Switching on re-runs that autocmd for the current buffer, so the map only
  -- opens (and mini.map only loads) over a real file
  {
    "M",
    "Minimap",
    persist = true,
    default = false,
    get = function()
      return vim.g.minimap_auto_open == true
    end,
    set = function(on)
      vim.g.minimap_auto_open = on
      if on then
        pcall(vim.api.nvim_exec_autocmds, "BufEnter", { group = "MiniMapAutoOpen", buffer = 0 })
      elseif loaded "mini.map" then
        require("mini.map").close()
      end
    end,
  },

  {
    "c",
    "Sticky Scroll",
    get = function()
      local context = loaded "treesitter-context"
      return context ~= nil and context.enabled()
    end,
    set = function(on)
      require("treesitter-context")[on and "enable" or "disable"]()
    end,
  },
}
