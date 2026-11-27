-- VS Code's gutter, drawn through 'statuscolumn' as fixed lanes, so no icon
-- hides another and the text never shifts when one appears:
--
--   [glyph][number] [bar][fold] text
--
--   glyph  breakpoints, test buttons and every other sign; a debugger sign
--          wins over the rest, then the highest priority
--   bar    git changes (gitsigns) and coverage, one cell; coverage wins while
--          it is shown, since it is switched on on purpose
--   fold   chevrons (utils/fold_gutter.lua)
--
-- Diagnostics stay out of the gutter (`signs = false` in configs/lspconfig.lua);
-- they show inline. A window with 'signcolumn' "no" gets no glyph/bar lanes.
local M = {}

local GLYPH, BAR = 2, 1 -- lane widths in cells

local fold = require "utils.fold_gutter"

-- Bar-lane signs by highlight group; coverage ranks above git
local bar_rank = { { "^Coverage", 2 }, { "^GitSigns", 1 } }

local function bar_rank_of(hl)
  for _, r in ipairs(bar_rank) do
    if hl:find(r[1]) then
      return r[2]
    end
  end
end

local function has_signs(win)
  return vim.wo[win].signcolumn ~= "no"
end

-- Highest ranked sign on `row` for each lane: `{ text, hl }` or nil
local function line_signs(buf, row)
  local marks = vim.api.nvim_buf_get_extmarks(buf, -1, { row, 0 }, { row, -1 }, { details = true, type = "sign" })
  local glyph, bar, glyph_rank, best_bar = nil, nil, -1, -1
  for _, m in ipairs(marks) do
    local d = m[4]
    local hl = d.sign_hl_group or ""
    local text = d.sign_text
    if text then
      local rank = bar_rank_of(hl)
      if rank then
        if rank > best_bar then
          bar, best_bar = { text, hl }, rank
        end
      else
        -- dap's signs are legacy ones named Dap*; rank them above the rest
        local r = (d.priority or 0) + ((d.sign_name or ""):find "^Dap" and 1e6 or 0)
        if r > glyph_rank then
          glyph, glyph_rank = { text, hl }, r
        end
      end
    end
  end
  return glyph, bar
end

-- `text` padded/cut to `width` cells, in `hl`
local function cell(sign, width)
  if not sign then
    return string.rep(" ", width)
  end
  local text = vim.fn.strcharpart(vim.trim(sign[1]), 0, width)
  text = text .. string.rep(" ", width - vim.fn.strdisplaywidth(text))
  return "%#" .. sign[2] .. "#" .. text:gsub("%%", "%%%%") .. "%*"
end

--- The whole column for v:lnum of the window being drawn.
function M.render()
  local win = vim.api.nvim_get_current_win()
  local fold_item = "%@v:lua.require'utils.fold_gutter'.click@" .. fold.render() .. "%T"
  if not has_signs(win) then
    return "%l " .. fold_item
  end
  local glyph, bar
  if vim.v.virtnum >= 0 then
    glyph, bar = line_signs(vim.api.nvim_win_get_buf(win), vim.v.lnum - 1)
    if vim.v.virtnum > 0 then
      glyph = nil -- wrapped line: the bar carries on, the icon doesn't
    end
  end
  return cell(glyph, GLYPH) .. "%l " .. cell(bar, BAR) .. fold_item
end

--- Which lane a click at `wincol` (getmousepos().wincol) in `win` landed in:
--- "glyph", "number", "bar", "fold", or nil for the text area.
function M.lane_at(win, wincol)
  local info = vim.fn.getwininfo(win)[1]
  if not info or wincol > info.textoff then
    return
  end
  local fold_w = fold.width(win)
  if wincol > info.textoff - fold_w then
    return "fold"
  end
  if has_signs(win) then
    if wincol <= GLYPH then
      return "glyph"
    end
    if wincol > info.textoff - fold_w - BAR then
      return "bar"
    end
  end
  return "number"
end

function M.setup()
  vim.o.statuscolumn = "%{%v:lua.require'utils.statuscolumn'.render()%}"
  fold.setup()
end

return M
