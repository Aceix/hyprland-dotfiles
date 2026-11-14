local remote = require "utils.remote"

-- :RemoteForward <port> / :RemoteForwardStop [port] (utils/port_forward.lua).
-- Defined when the spec loads, not when the plugin does, so they also exist
-- on the remote server, where you type them.
require("utils.port_forward").setup()

return {
  devpod = {
    -- The isolated CLI under data/, then PATH, then DevPod.app's (core.lua)
    binary = require("devcontainer.core").devpod_path(),
    -- Not "recurse_up": in v0.3.12 it crashes outside a devcontainer project
    -- (devpod_utils checks find_upwards() against "", plenary returns nil)
    search_style = "current_dir_only",
    container_list = "all",
  },

  remote = {
    copy_dirs = {
      -- Copy the whole config; lazy.nvim installs plugins on the remote, and
      -- configs/lazy.lua turns off the local-only ones there. data/state/cache
      -- aren't copied: mason and blink binaries built for macOS won't run on
      -- a Linux host.
      config = {
        base = vim.fn.stdpath "config",
        dirs = "*",
        compression = { enabled = true },
      },
      -- Parts of data/ worth having there, each only if it exists here
      -- (remote-nvim aborts the connect on a missing local path):
      -- * neotest-java's JUnit runner jar (from :NeotestJava setup)
      -- * treesitter parsers (site/), built on Linux: they need only glibc
      --   2.14, so most Linux remotes load them without building anything.
      --   Left out for remotes on another OS/CPU (utils/remote.lua); the
      --   remote fixes up the rest (utils/ts_parsers.lua).
      data = (function()
        local base = vim.fn.stdpath "data"
        local dirs = {}
        if vim.uv.fs_stat(base .. "/neotest-java") then
          dirs[#dirs + 1] = "neotest-java"
        end
        if vim.fn.has "linux" == 1 and vim.uv.fs_stat(base .. "/site/parser") then
          dirs[#dirs + 1] = "site"
        end
        return #dirs > 0 and { base = base, dirs = dirs, compression = { enabled = true } } or nil
      end)(),
    },
  },

  client_callback = remote.open_client,
}

