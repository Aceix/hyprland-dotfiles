return {
  ui = {
    border = "rounded",
    notification_style = "native",
  },
  decorations = {
    statusline = {
      app_version = true,
      device = true,
    },
  },
  widget_guides = {
    enabled = true,
  },
  closing_tags = {
    highlight = "Comment",
    prefix = " // ",
    enabled = true,
  },
  -- Registers the dart/flutter dap adapters from the SDK's own debug adapter
  -- (mason-nvim-dap leaves dart alone, see configs/dap.lua)
  debugger = {
    enabled = true,
  },
  lsp = {
    color_factor = 0.2,
    settings = {
      showTodos = true,
      completeFunctionCalls = true,
    },
  },
}
