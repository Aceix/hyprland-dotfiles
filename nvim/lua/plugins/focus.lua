-- Golden-ratio auto-resize of the focused split (<leader>uf toggles it).
-- focus.nvim only leaves a window alone when it carries b:focus_disable /
-- w:focus_disable, so every non-code window (side bar, terminal pane, dap-ui,
-- Trouble, quickfix, chats, ...) is flagged below; anything not flagged gets
-- squashed by the next resize.
local exclude_ft = {
  gitcommit = true,
  NvimTree = true,
  NeogitStatus = true,
  gitpanel = true,
}

-- Code = a listed file buffer. "nowrite" is image.nvim's buftype for image
-- files it displays, which should resize like any other editor split.
local function is_code_buf(buf)
  local bt = vim.bo[buf].buftype
  return (bt == "" or bt == "nowrite") and vim.bo[buf].buflisted and not exclude_ft[vim.bo[buf].filetype]
end

return {
  "nvim-focus/focus.nvim",
  version = "*",
  event = "VeryLazy",
  cmd = { "FocusToggle", "FocusEnable", "FocusDisable", "FocusEqualise", "FocusMaximise" },
  opts = {
    -- resizing only: leave cursorline / signcolumn alone in unfocused windows
    ui = { cursorline = false, signcolumn = false },
  },
  config = function(_, opts)
    -- Registered before focus.nvim's own WinEnter handler, so the flag is
    -- already right when it resizes
    local group = vim.api.nvim_create_augroup("FocusExclude", { clear = true })
    vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter", "FileType", "TermOpen", "OptionSet" }, {
      group = group,
      callback = function(ev)
        if ev.event == "OptionSet" and not vim.tbl_contains({ "buftype", "buflisted" }, ev.match) then
          return
        end
        local buf = vim.api.nvim_get_current_buf()
        vim.b[buf].focus_disable = not is_code_buf(buf)
      end,
    })
    -- Flag what's already on screen when the plugin loads
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local buf = vim.api.nvim_win_get_buf(win)
      vim.b[buf].focus_disable = not is_code_buf(buf)
    end

    require("focus").setup(opts)
  end,
}
