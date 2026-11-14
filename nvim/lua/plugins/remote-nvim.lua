-- Remote development over SSH and devcontainers, like VS Code's Remote - SSH
-- and Dev Containers. This config is copied to the remote and runs there
-- (see configs/remote-nvim.lua); SSH clients open in a new terminal tab, while
-- DevPods replace the current window (devcontainer/client.lua). Devcontainers
-- go through DevPod. <leader>rs is the launcher (devcontainer/menu.lua);
-- <leader>rD the same list narrowed to Dev Containers.
return {
  "amitds1997/remote-nvim.nvim",
  version = "*",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-telescope/telescope.nvim",
  },
  cmd = {
    "RemoteStart",
    "RemoteStop",
    "RemoteInfo",
    "RemoteCleanup",
    "RemoteConfigDel",
    "RemoteLog",
    "RemoteRefresh",
    "RemoteReconnect",
    "Devcontainer",
  },
  keys = {
    { "<leader>rs", "<cmd>RemoteStart<cr>", desc = "Remote: Open (SSH / Dev Containers)" },
    { "<leader>rD", "<cmd>Devcontainer<cr>", desc = "Dev Containers: Actions" },
    { "<leader>rR", "<cmd>Devcontainer rebuild<cr>", desc = "Dev Containers: Rebuild and reopen" },
    { "<leader>rq", "<cmd>Devcontainer detach<cr>", desc = "Dev Containers: Detach (stops it)" },
    { "<leader>rr", "<cmd>RemoteRefresh<cr>", desc = "Remote: Re-copy config + sync plugins" },
    { "<leader>rS", "<cmd>RemoteStop<cr>", desc = "Remote: Stop session" },
    { "<leader>ri", "<cmd>RemoteInfo<cr>", desc = "Remote: Session info" },
    { "<leader>rc", "<cmd>RemoteCleanup<cr>", desc = "Remote: Clean up host" },
    { "<leader>rd", "<cmd>RemoteConfigDel<cr>", desc = "Remote: Forget saved host" },
    { "<leader>rl", "<cmd>RemoteLog<cr>", desc = "Remote: Open log" },
  },
  -- "Reopen in Container" hint, before (and without) loading the plugin
  init = function()
    require("devcontainer").watch()
  end,
  opts = require "configs.remote-nvim",
  config = function(_, opts)
    require("remote-nvim").setup(opts)
    local remote = require "utils.remote"
    remote.keep_progress_view()
    remote.secure_launch()
    remote.track_sessions()
    remote.ask_on_quit()
    require("devcontainer").setup()

    vim.api.nvim_create_user_command("RemoteReconnect", remote.reconnect, {
      desc = "Retry a reconnect that's waiting for a password / passphrase / 2FA code",
    })

    vim.api.nvim_create_user_command("RemoteRefresh", function(cmd)
      local host = vim.trim(cmd.args)
      if host ~= "" then
        return remote.refresh(host)
      end
      local hosts = remote.hosts()
      if #hosts == 1 then
        return remote.refresh(hosts[1])
      end
      vim.ui.select(hosts, { prompt = "Refresh config on which host?" }, function(choice)
        if choice then
          remote.refresh(choice)
        end
      end)
    end, {
      nargs = "?",
      desc = "Re-copy this config to a remote host, sync its plugins, restart its sessions",
      complete = function(lead)
        return vim.tbl_filter(function(h)
          return h:find(lead, 1, true) == 1
        end, remote.hosts())
      end,
    })
  end,
}
