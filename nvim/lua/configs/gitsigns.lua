-- GitLens' editor features: blame at the end of the current line, blame
-- hover and full-file blame (mapped in lua/mappings.lua), and gutter change
-- markers with VS Code's next/previous change keys.
return {
  current_line_blame = true,
  current_line_blame_opts = {
    virt_text = true,
    virt_text_pos = "eol",
    delay = 400,
    ignore_whitespace = false,
  },
  -- "You, 3 days ago • Fix the thing", as GitLens shows it
  current_line_blame_formatter = " <author>, <author_time:%R> • <summary>",
  current_line_blame_formatter_nc = " You • Uncommitted changes",
  preview_config = { border = "rounded" },

  on_attach = function(bufnr)
    local gs = require "gitsigns"
    local function map(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, desc = desc })
    end

    -- Diff mode keeps ]c / [c; ]h / [h always move between hunks
    local function nav(dir)
      return function()
        gs.nav_hunk(dir, { target = "all" })
      end
    end
    map("n", "]h", nav "next", "Next change")
    map("n", "[h", nav "prev", "Previous change")
    -- VS Code: Go to Next / Previous Change
    map("n", "<A-F5>", nav "next", "Next change")
    map("n", "<S-A-F5>", nav "prev", "Previous change")

    map({ "o", "x" }, "ih", gs.select_hunk, "Select hunk")
  end,
}
