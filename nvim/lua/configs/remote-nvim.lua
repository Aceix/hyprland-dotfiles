local remote = require "utils.remote"

-- :RemoteForward <port> / :RemoteForwardStop [port] (utils/port_forward.lua).
-- Defined when the spec loads, not when the plugin does, so they also exist
-- on the remote server, where you type them.
require("utils.port_forward").setup()

return {
  devpod = {
    -- DevPod.app ships its CLI as devpod-cli inside the bundle, not on PATH
    binary = remote.bin("devpod", "/Applications/DevPod.app/Contents/MacOS/devpod-cli"),
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
      -- Only the platform-independent bits of data/: neotest-java's JUnit
      -- runner jar (from :NeotestJava setup). Listed only if it exists here,
      -- since remote-nvim aborts the connect on a missing local path.
      data = vim.uv.fs_stat(vim.fn.stdpath "data" .. "/neotest-java") and {
        base = vim.fn.stdpath "data",
        dirs = { "neotest-java" },
        compression = { enabled = true },
      } or nil,
    },
  },

  client_callback = remote.open_client,
}

