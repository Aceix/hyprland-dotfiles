return function(_, opts)
  local neoscroll = require "neoscroll"

  neoscroll.setup(vim.tbl_extend("force", opts, {
    hide_cursor = true,
    stop_eof = true,
    easing = "quadratic",
    post_hook = function(info)
      if info == "center" then
        vim.cmd "normal! zz"
      end
    end,
  }))

  -- PageUp / PageDown: smooth half-page scroll, then centre the cursor line
  for key, lines in pairs { ["<PageUp>"] = -0.5, ["<PageDown>"] = 0.5 } do
    vim.keymap.set({ "n", "i", "v" }, key, function()
      neoscroll.scroll(lines, { move_cursor = true, duration = 250, easing = "quadratic", info = "center" })
    end, { desc = lines < 0 and "Smooth scroll half page up" or "Smooth scroll half page down" })
  end
end
