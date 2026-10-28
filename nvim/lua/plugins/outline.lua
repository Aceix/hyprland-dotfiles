-- Docked in the side bar under the Explorer or in its own right pane;
-- utils/outline_dock.lua does the placing and switching.
return {
  "hedyhli/outline.nvim",
  cmd = { "Outline", "OutlineOpen" },
  keys = {
    {
      "<leader>co",
      function()
        require("utils.outline_dock").toggle()
      end,
      desc = "Toggle Symbol Outline",
    },
    {
      "<leader>cO",
      function()
        require("utils.outline_dock").switch()
      end,
      desc = "Outline: Side Bar <-> Right Pane",
    },
  },
  opts = function()
    return {
      outline_window = { position = require("utils.outline_dock").dock() },
      -- Folds change only when toggled, never by following the cursor
      symbol_folding = { auto_unfold = { hovered = false } },
    }
  end,
  config = function(_, opts)
    require("outline").setup(opts)

    -- Alphabetical, like VS Code's "Sort By: Name". outline.nvim only sorts
    -- by position, in parser.parse; swap the sort in for that call alone
    -- (merging LSP and JSX symbols needs the position order)
    local parser, lsp = require "outline.parser", require "outline.utils.lsp"
    local by_position, parse = lsp.sort_symbols, parser.parse
    local function by_name(symbols)
      table.sort(symbols, function(a, b)
        return a.name:lower() < b.name:lower()
      end)
      for _, symbol in ipairs(symbols) do
        if symbol.children then
          by_name(symbol.children)
        end
      end
      return symbols
    end
    parser.parse = function(...)
      lsp.sort_symbols = by_name
      local ok, items = pcall(parse, ...)
      lsp.sort_symbols = by_position
      if not ok then
        error(items, 0)
      end
      return items
    end
  end,
}
