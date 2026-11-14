vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- No-op unless this is a remote-nvim server; see utils/remote.lua
local remote = require "utils.remote"
remote.server_init()
-- Inside a container: its keys and the hand-back to the Neovim it came from
-- (devcontainer/client.lua). Before the theme below, which a brand-new remote
-- doesn't have compiled yet on its first start.
if remote.is_remote then
  require("devcontainer").setup()
end

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    branch = "v2.5",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

-- load theme. NvChad compiles it when base46 is installed; on a fresh remote
-- that install step can fail (plugins still arriving), and without the cache
-- this file stops here: no options, autocmds or mappings. So build it now.
if not vim.uv.fs_stat(vim.g.base46_cache .. "defaults") then
  pcall(function()
    require("base46").load_all_highlights()
  end)
end
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "autocmds"


vim.schedule(function()
  require "mappings"
end)
