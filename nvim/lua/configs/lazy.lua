-- Plugins that only make sense on this machine (GUI image protocol, local AI
-- tooling, SDKs, gh-authenticated tools, remote-nvim itself). They're switched
-- off when this config runs as a remote-nvim server; see utils/remote.lua.
-- nvim-jdtls runs on remotes too: it only needs Java and Mason's jdtls there.
local local_only = {
  ["remote-nvim.nvim"] = true,
  ["image.nvim"] = true,
  ["mcphub.nvim"] = true,
  ["opencode.nvim"] = true,
  ["live-share.nvim"] = true,
  ["flutter-tools.nvim"] = true,
  ["posting.nvim"] = true,
  ["atlas.nvim"] = true,
}
local is_remote = require("utils.remote").is_remote

return {
  defaults = {
    lazy = true,
    cond = function(plugin)
      return not (is_remote and local_only[plugin.name])
    end,
  },
  install = { colorscheme = { "nvchad" } },

  ui = {
    icons = {
      ft = "",
      lazy = "󰂠 ",
      loaded = "",
      not_loaded = "",
    },
  },

  performance = {
    rtp = {
      disabled_plugins = {
        "2html_plugin",
        "tohtml",
        "getscript",
        "getscriptPlugin",
        "gzip",
        "logipat",
        "netrw",
        "netrwPlugin",
        "netrwSettings",
        "netrwFileHandlers",
        "matchit",
        "tar",
        "tarPlugin",
        "rrhelper",
        "spellfile_plugin",
        "vimball",
        "vimballPlugin",
        "zip",
        "zipPlugin",
        "tutor",
        "rplugin",
        "syntax",
        "synmenu",
        "optwin",
        "compiler",
        "bugreport",
        "ftplugin",
      },
    },
  },
}
