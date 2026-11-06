-- Quickfix / location list: `e` swaps Trouble's view (what :copen / :lopen
-- show, utils/term.lua) for the editable one (quicker.nvim)
local edit = {
  e = {
    action = function(view)
      local main = view:main()
      require("utils.term").edit_list(view.opts.mode, main and main.win)
    end,
    desc = "Edit the List",
  },
}

return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  opts = {
    -- An empty list opens too, with a note (below), instead of a warning
    open_no_results = true,
    warn_no_results = false,
    modes = {
      -- Problems grouped by severity, then file (see the fold state below)
      diagnostics = {
        groups = {
          { "severity", format = "{severity_icon} {severity} {count}" },
          { "filename", format = "{file_icon} {basename} {count}" },
        },
      },
      qflist = { keys = edit },
      loclist = { keys = edit },
    },
  },
  config = function(_, opts)
    require("trouble").setup(opts)

    -- Bottom lists (Problems, quickfix, ...) take the terminal pane's place,
    -- like a tab of VS Code's panel (utils/term.lua). Trouble splits with
    -- autocmds off, so this is the one place that sees the window open. It
    -- opens at the panel's height, so nothing jumps when it's adopted.
    local Window = require "trouble.view.window"
    local mount = Window.mount
    function Window:mount()
      local bottom = self.opts.type == "split" and self.opts.position == "bottom"
      if bottom then
        self.opts.size = require("utils.term").height()
      end
      mount(self)
      if bottom and self.win then
        require("utils.term").adopt(self.win)
      end
    end

    -- Lists open with only their top level expanded (Problems: the
    -- severities, their files collapsed), the first time each list opens in
    -- this session; after that, what you expand or collapse stays as it was,
    -- though Trouble builds a fresh view on every open. Groups that show up
    -- later start collapsed too, unless you've opened everything (zR).
    local Render = require "trouble.view.render"
    local fold_state = {} -- by mode + filter
    local function keep_folds(view)
      local key = view.opts.mode .. vim.inspect(view.opts.filter or {})
      local st = fold_state[key] or { folded = {}, seen = {} }
      fold_state[key], view._fold_state = st, st
      view.renderer._folded, view.renderer._seen = st.folded, st.seen
      -- Set before Trouble's own first-fold pass, which re-renders through
      -- its throttle and loses that render. Render:node folds instead.
      view.renderer.foldlevel = st.level or 1
    end

    -- A group seen for the first time is folded if it's deeper than the
    -- fold level (on the first render, that's every one below the top)
    local node = Render.node
    function Render:node(n, ...)
      if self._seen and not n:is_leaf() and not self._seen[n.id] then
        self._seen[n.id] = true
        if self.foldlevel and n:depth() > self.foldlevel then
          self._folded[n.id] = true
        end
      end
      return node(self, n, ...)
    end

    local View = require "trouble.view"

    -- Closed from inside it (q, ...), a bottom list gives up its tab
    -- (utils/term.lua); Trouble moves to the code window before closing it
    local close = View.close
    function View:close()
      if self.win:valid() and vim.api.nvim_get_current_win() == self.win.win then
        vim.w[self.win.win].nvterm_close = true
      end
      return close(self)
    end

    -- Like VS Code's panel, an empty list says so instead of staying blank
    local render = View.render
    function View:render()
      local count = self:count()
      if self.win:valid() then
        -- what decides whether the list gets a tab in the bottom panel
        require("utils.term").set_count(self.opts.mode, count)
      end
      if not (self.win:valid() and count == 0) then
        if self.win:valid() and self.renderer._seen == nil then
          keep_folds(self)
        end
        local ret = render(self)
        if self._fold_state then
          self._fold_state.level = self.renderer.foldlevel
        end
        return ret
      end
      local text = self.opts.mode == "diagnostics" and "No problems have been detected in the workspace."
        or "No results."
      self.renderer:clear()
      self.renderer:nl()
      self.renderer:append("  \u{f05d} ", "DiagnosticOk"):append(text, "Comment")
      self.renderer:render(self.win.buf)
      vim.schedule(self.first_render.resolve)
    end
  end,
}
