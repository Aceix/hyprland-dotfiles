 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#0f1417',
    base01 = '#1c2023',
    base02 = '#262b2e',
    base03 = '#8a9297',
    base04 = '#c0c7cd',
    base05 = '#dfe3e7',
    base06 = '#dfe3e7',
    base07 = '#dfe3e7',
    base08 = '#ffb4ab',
    base09 = '#cac1ea',
    base0A = '#b5c9d7',
    base0B = '#8fcef3',
    base0C = '#cac1ea',
    base0D = '#8fcef3',
    base0E = '#b5c9d7',
    base0F = '#d1e5f4',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#dfe3e7',          bg = '#0f1417' })
  hi('TelescopeBorder',         { fg = '#8a9297',             bg = '#0f1417' })
  hi('TelescopePromptNormal',   { fg = '#dfe3e7',          bg = '#0f1417' })
  hi('TelescopePromptBorder',   { fg = '#8a9297',             bg = '#0f1417' })
  hi('TelescopePromptPrefix',   { fg = '#8fcef3',             bg = '#0f1417' })
  hi('TelescopePromptCounter',  { fg = '#c0c7cd',  bg = '#0f1417' })
  hi('TelescopePromptTitle',    { fg = '#0f1417',             bg = '#8fcef3' })
  hi('TelescopePreviewTitle',   { fg = '#0f1417',             bg = '#b5c9d7' })
  hi('TelescopeResultsTitle',   { fg = '#0f1417',             bg = '#cac1ea' })
  hi('TelescopeSelection',      { fg = '#dfe3e7',          bg = '#262b2e' })
  hi('TelescopeSelectionCaret', { fg = '#8fcef3',             bg = '#262b2e' })
  hi('TelescopeMatching',       { fg = '#8fcef3',             bold = true })

  -- mini.pick
  hi('MiniPickNormal',         { fg = '#dfe3e7',          bg = '#0f1417' })
  hi('MiniPickBorder',         { fg = '#8a9297',             bg = '#0f1417' })
  hi('MiniPickPrompt',   { fg = '#dfe3e7',          bg = '#0f1417' })
  hi('MiniPickPromptPrefix',   { fg = '#8fcef3',             bg = '#0f1417' })
  hi('MiniPickBorderText',    { fg = '#0f1417',             bg = '#8fcef3' })
  hi('MiniPickMatchCurrent',      { fg = '#dfe3e7',          bg = '#262b2e' })
  hi('MiniPickPromptCaret', { fg = '#8fcef3',             bg = '#262b2e' })
  hi('MiniPickMatchRanges',       { fg = '#8fcef3',             bold = true })
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
