 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#000000',
    base01 = '#111417',
    base02 = '#1a1d22',
    base03 = '#8c9199',
    base04 = '#c3c7cf',
    base05 = '#e1e2e8',
    base06 = '#e1e2e8',
    base07 = '#e1e2e8',
    base08 = '#ffb4ab',
    base09 = '#d6bee5',
    base0A = '#bac8db',
    base0B = '#9fcafc',
    base0C = '#d6bee5',
    base0D = '#9fcafc',
    base0E = '#bac8db',
    base0F = '#d6e4f7',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#e1e2e8',          bg = '#000000' })
  hi('TelescopeBorder',         { fg = '#8c9199',             bg = '#000000' })
  hi('TelescopePromptNormal',   { fg = '#e1e2e8',          bg = '#000000' })
  hi('TelescopePromptBorder',   { fg = '#8c9199',             bg = '#000000' })
  hi('TelescopePromptPrefix',   { fg = '#9fcafc',             bg = '#000000' })
  hi('TelescopePromptCounter',  { fg = '#c3c7cf',  bg = '#000000' })
  hi('TelescopePromptTitle',    { fg = '#000000',             bg = '#9fcafc' })
  hi('TelescopePreviewTitle',   { fg = '#000000',             bg = '#bac8db' })
  hi('TelescopeResultsTitle',   { fg = '#000000',             bg = '#d6bee5' })
  hi('TelescopeSelection',      { fg = '#e1e2e8',          bg = '#1a1d22' })
  hi('TelescopeSelectionCaret', { fg = '#9fcafc',             bg = '#1a1d22' })
  hi('TelescopeMatching',       { fg = '#9fcafc',             bold = true })

  -- mini.pick
  hi('MiniPickNormal',         { fg = '#e1e2e8',          bg = '#000000' })
  hi('MiniPickBorder',         { fg = '#8c9199',             bg = '#000000' })
  hi('MiniPickPrompt',   { fg = '#e1e2e8',          bg = '#000000' })
  hi('MiniPickPromptPrefix',   { fg = '#9fcafc',             bg = '#000000' })
  hi('MiniPickBorderText',    { fg = '#000000',             bg = '#9fcafc' })
  hi('MiniPickMatchCurrent',      { fg = '#e1e2e8',          bg = '#1a1d22' })
  hi('MiniPickPromptCaret', { fg = '#9fcafc',             bg = '#1a1d22' })
  hi('MiniPickMatchRanges',       { fg = '#9fcafc',             bold = true })
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
