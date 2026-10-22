 local M = {}

function M.setup()
  require('base16-colorscheme').setup({
    base00 = '#11140e',
    base01 = '#1e211a',
    base02 = '#282b24',
    base03 = '#8e9285',
    base04 = '#c4c8ba',
    base05 = '#e2e3d9',
    base06 = '#e2e3d9',
    base07 = '#e2e3d9',
    base08 = '#ffb4ab',
    base09 = '#a0cfcd',
    base0A = '#bfcbad',
    base0B = '#afd18c',
    base0C = '#a0cfcd',
    base0D = '#afd18c',
    base0E = '#bfcbad',
    base0F = '#dbe7c8',
  })

  local hi = function(group, opts)
    vim.api.nvim_set_hl(0, group, opts)
  end

  -- telescope.nvim
  hi('TelescopeNormal',         { fg = '#e2e3d9',          bg = '#11140e' })
  hi('TelescopeBorder',         { fg = '#8e9285',             bg = '#11140e' })
  hi('TelescopePromptNormal',   { fg = '#e2e3d9',          bg = '#11140e' })
  hi('TelescopePromptBorder',   { fg = '#8e9285',             bg = '#11140e' })
  hi('TelescopePromptPrefix',   { fg = '#afd18c',             bg = '#11140e' })
  hi('TelescopePromptCounter',  { fg = '#c4c8ba',  bg = '#11140e' })
  hi('TelescopePromptTitle',    { fg = '#11140e',             bg = '#afd18c' })
  hi('TelescopePreviewTitle',   { fg = '#11140e',             bg = '#bfcbad' })
  hi('TelescopeResultsTitle',   { fg = '#11140e',             bg = '#a0cfcd' })
  hi('TelescopeSelection',      { fg = '#e2e3d9',          bg = '#282b24' })
  hi('TelescopeSelectionCaret', { fg = '#afd18c',             bg = '#282b24' })
  hi('TelescopeMatching',       { fg = '#afd18c',             bold = true })

  -- mini.pick
  hi('MiniPickNormal',         { fg = '#e2e3d9',          bg = '#11140e' })
  hi('MiniPickBorder',         { fg = '#8e9285',             bg = '#11140e' })
  hi('MiniPickPrompt',   { fg = '#e2e3d9',          bg = '#11140e' })
  hi('MiniPickPromptPrefix',   { fg = '#afd18c',             bg = '#11140e' })
  hi('MiniPickBorderText',    { fg = '#11140e',             bg = '#afd18c' })
  hi('MiniPickMatchCurrent',      { fg = '#e2e3d9',          bg = '#282b24' })
  hi('MiniPickPromptCaret', { fg = '#afd18c',             bg = '#282b24' })
  hi('MiniPickMatchRanges',       { fg = '#afd18c',             bold = true })
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
