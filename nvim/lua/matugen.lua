 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#131315',
    base01 = '#1f1f21',
    base02 = '#2a2a2c',
    base03 = '#909098',
    base04 = '#c6c6ce',
    base05 = '#e4e2e4',
    base06 = '#e4e2e4',
    base07 = '#e4e2e4',
    base08 = '#ffb4ab',
    base09 = '#e2bbd7',
    base0A = '#c4c6d4',
    base0B = '#bdc6e6',
    base0C = '#e2bbd7',
    base0D = '#bdc6e6',
    base0E = '#c4c6d4',
    base0F = '#e0e2f1',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#e4e2e4',          bg = '#131315' })
  hi('TelescopeBorder',         { fg = '#909098',             bg = '#131315' })
  hi('TelescopePromptNormal',   { fg = '#e4e2e4',          bg = '#131315' })
  hi('TelescopePromptBorder',   { fg = '#909098',             bg = '#131315' })
  hi('TelescopePromptPrefix',   { fg = '#bdc6e6',             bg = '#131315' })
  hi('TelescopePromptCounter',  { fg = '#c6c6ce',  bg = '#131315' })
  hi('TelescopePromptTitle',    { fg = '#131315',             bg = '#bdc6e6' })
  hi('TelescopePreviewTitle',   { fg = '#131315',             bg = '#c4c6d4' })
  hi('TelescopeResultsTitle',   { fg = '#131315',             bg = '#e2bbd7' })
  hi('TelescopeSelection',      { fg = '#e4e2e4',          bg = '#2a2a2c' })
  hi('TelescopeSelectionCaret', { fg = '#bdc6e6',             bg = '#2a2a2c' })
  hi('TelescopeMatching',       { fg = '#bdc6e6',             bold = true })

  -- mini.pick
  hi('MiniPickNormal',         { fg = '#e4e2e4',          bg = '#131315' })
  hi('MiniPickBorder',         { fg = '#909098',             bg = '#131315' })
  hi('MiniPickPrompt',   { fg = '#e4e2e4',          bg = '#131315' })
  hi('MiniPickPromptPrefix',   { fg = '#bdc6e6',             bg = '#131315' })
  hi('MiniPickBorderText',    { fg = '#131315',             bg = '#bdc6e6' })
  hi('MiniPickMatchCurrent',      { fg = '#e4e2e4',          bg = '#2a2a2c' })
  hi('MiniPickPromptCaret', { fg = '#bdc6e6',             bg = '#2a2a2c' })
  hi('MiniPickMatchRanges',       { fg = '#bdc6e6',             bold = true })
end

-- Register a signal handler for SIGUSR1 (matugen updates).
-- The handler re-requires this module, which re-runs the code below, so the
-- previous handle is stopped first; otherwise handlers double on every signal.
if _G.__matugen_signal then
  _G.__matugen_signal:stop()
  _G.__matugen_signal:close()
end

local signal = vim.uv.new_signal()
_G.__matugen_signal = signal
signal:start(
  'sigusr1',
  vim.schedule_wrap(function()
    package.loaded['matugen'] = nil
    require('matugen').setup()
  end)
)

return M
