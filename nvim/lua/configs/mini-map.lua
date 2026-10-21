return function()
  local map = require "mini.map"

  map.setup {
    integrations = {
      map.gen_integration.builtin_search(),
      map.gen_integration.diagnostic(),
      map.gen_integration.gitsigns(), -- uses the gitsigns.nvim already in this config
    },
    symbols = {
      encode = map.gen_encode_symbols.dot "4x2",
    },
    window = {
      side = "right",
      width = 10,
      winblend = 15,
      show_integration_count = false,
    },
  }

  -- mini.map's float covers the editor's whole height, so it drew over the
  -- terminal/Problems panel and dap-ui's REPL strip. Like VS Code's, keep it
  -- inside the code window it maps instead: same height, at its right edge.
  -- That window ("anchor") is the current one while it shows a file, else the
  -- one last mapped. mini.map has no option for this; its window geometry and
  -- updaters live on its internal table, reached through an upvalue. If a
  -- mini.map update renames them, this leaves mini.map's own behaviour.
  local H
  for i = 1, 50 do
    local name, value = debug.getupvalue(map.refresh, i)
    if not name then
      break
    end
    if name == "H" then
      H = value
      break
    end
  end
  if
    type(H) ~= "table"
    or type(H.normalize_window_options) ~= "function"
    or type(H.update_map_lines) ~= "function"
  then
    return
  end

  local api = vim.api
  local anchors = {} -- tabpage -> code window the map belongs to

  -- mini.map's own test for a buffer it maps
  local function is_source(win)
    return api.nvim_win_get_config(win).relative == "" and vim.tbl_contains({ "", "help" }, vim.bo[api.nvim_win_get_buf(win)].buftype)
  end

  local function anchor()
    local tab, cur = api.nvim_get_current_tabpage(), api.nvim_get_current_win()
    if is_source(cur) then
      anchors[tab] = cur
    end
    local win = anchors[tab]
    if win and api.nvim_win_is_valid(win) and api.nvim_win_get_tabpage(win) == tab then
      return win
    end
    anchors[tab] = nil
    -- that window closed: another one showing the mapped buffer
    for _, w in ipairs(vim.fn.win_findbuf(map.current.buf_data.source or -1)) do
      if api.nvim_win_get_tabpage(w) == tab and is_source(w) then
        anchors[tab] = w
        return w
      end
    end
  end

  local normalize = H.normalize_window_options
  H.normalize_window_options = function(win_opts, full)
    local res = normalize(win_opts, full)
    local win = anchor()
    if win then
      local info = vim.fn.getwininfo(win)[1]
      local row, col = unpack(api.nvim_win_get_position(win))
      res.relative = "editor"
      res.row = row + info.winbar -- below the breadcrumbs
      res.height = math.max(info.height, 1)
      if res.anchor == "NW" then
        res.col = col
      else
        res.col = col + api.nvim_win_get_width(win)
      end
    end
    return res
  end

  -- The updaters read the current window (its buffer, view, cursor); from the
  -- terminal or a panel, have them read the code window instead
  for _, key in ipairs { "update_map_lines", "update_map_scrollbar", "update_map_integrations" } do
    local update = H[key]
    if type(update) == "function" then
      H[key] = function(...)
        local win = anchor()
        if win and win ~= api.nvim_get_current_win() then
          local args = { ... }
          return api.nvim_win_call(win, function()
            return update(unpack(args))
          end)
        end
        return update(...)
      end
    end
  end

  -- Follow the code window as panels open, close and get resized. Only when
  -- it actually moved: WinClosed also fires for every completion menu and
  -- hover, and a refresh re-encodes the whole buffer.
  local group = api.nvim_create_augroup("MiniMapAnchor", { clear = true })
  local pending = false
  local function follow()
    pending = false
    local tab = api.nvim_get_current_tabpage()
    local win = map.current.win_data[tab]
    if not (win and api.nvim_win_is_valid(win)) or not map.current.opts.window then
      return
    end
    local want = H.normalize_window_options(map.current.opts.window, false)
    local have = api.nvim_win_get_config(win)
    if want.row ~= have.row or want.col ~= have.col or want.height ~= have.height then
      map.refresh()
    end
  end
  api.nvim_create_autocmd({ "WinResized", "WinClosed", "VimResized", "TabClosed" }, {
    group = group,
    callback = function(args)
      if args.event == "TabClosed" then
        for tab in pairs(anchors) do
          if not api.nvim_tabpage_is_valid(tab) then
            anchors[tab] = nil
          end
        end
        return
      end
      if args.event == "WinClosed" then
        local closed = tonumber(args.match)
        if closed and api.nvim_win_is_valid(closed) and api.nvim_win_get_config(closed).relative ~= "" then
          return
        end
      end
      if not pending then
        pending = true
        vim.schedule(follow)
      end
    end,
  })
end
