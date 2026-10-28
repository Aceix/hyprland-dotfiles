-- Side bar views stacked in edgy (configs/edgy.lua): the bottom view's
-- share of the height, changed by dragging the line between the two and
-- kept across restarts (upper-case g: vars, which shada's '!' keeps). The
-- view above takes whatever is left.

local M = {}

local api = vim.api

-- The bottom view's filetype -> the view above it, its g: var, default share
local splits = {
  Outline = { top = "NvimTree", var = "OUTLINE_HEIGHT", default = 0.5 },
  gitpanel = { top = "NeogitStatus", var = "SCM_HEIGHT", default = 0.45 },
}

---@param ft string the bottom view's filetype
function M.height(ft)
  local split = splits[ft]
  return vim.g[split.var] or split.default
end

-- Each split on screen, as { ft, bottom, top } windows, when both views are
-- in the side bar (the outline can be in its own pane instead)
local function on_screen()
  local wins = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      wins[vim.bo[api.nvim_win_get_buf(win)].filetype] = win
    end
  end
  local res = {}
  for ft, split in pairs(splits) do
    local bottom, top = wins[ft], wins[split.top]
    if bottom and top and api.nvim_win_get_position(bottom)[2] == api.nvim_win_get_position(top)[2] then
      res[#res + 1] = { ft = ft, bottom = bottom, top = top }
    end
  end
  return res
end

function M.setup()
  local group = api.nvim_create_augroup("SidebarSplit", { clear = true })

  -- Dragging the line: edgy snaps heights it didn't set back to the view's
  -- size on WinResized, so record the new share first (this runs before
  -- edgy's handler, which loads on VeryLazy). A drag moves only the line
  -- between the two views: their total stays, and the bottom one is no
  -- longer at edgy's size. Anything else (a message growing the command
  -- line, the screen resizing, edgy re-laying out, the view still being
  -- docked) is not a drag, so edgy puts the set size back.
  local totals = {} ---@type table<integer, integer> bottom window -> last total height

  local function target(s, total)
    -- edgy's sizing
    return math.floor(total * M.height(s.ft))
  end

  api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      for _, s in ipairs(on_screen()) do
        local h = api.nvim_win_get_height(s.bottom)
        local total = h + api.nvim_win_get_height(s.top)
        if totals[s.bottom] == total and h ~= target(s, total) then
          -- + 0.5: edgy's floor gives back exactly h
          vim.g[splits[s.ft].var] = math.max(0.15, math.min((h + 0.5) / total, 0.85))
        end
        totals[s.bottom] = total
      end
    end,
  })
  api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      totals[tonumber(ev.match)] = nil
    end,
  })
end

return M
