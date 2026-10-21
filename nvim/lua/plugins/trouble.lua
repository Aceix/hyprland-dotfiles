return {
  "folke/trouble.nvim",
  cmd = "Trouble",
  opts = {
    -- An empty list opens too, with a note (below), instead of a warning
    open_no_results = true,
    warn_no_results = false,
  },
  config = function(_, opts)
    require("trouble").setup(opts)

    -- Bottom lists (Problems, quickfix, ...) take the terminal pane's place,
    -- like a tab of VS Code's panel (utils/term.lua). Trouble splits with
    -- autocmds off, so this is the one place that sees the window open.
    local Window = require "trouble.view.window"
    local mount = Window.mount
    function Window:mount()
      mount(self)
      if self.opts.type == "split" and self.opts.position == "bottom" and self.win then
        require("utils.term").adopt(self.win)
      end
    end

    -- Like VS Code's panel, an empty list says so instead of staying blank
    local View = require "trouble.view"
    local render = View.render
    function View:render()
      if not (self.win:valid() and self:count() == 0) then
        return render(self)
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
