-- The display name peers see is kept in Neovim's state, not here: it's asked
-- for the first time a session is hosted or joined, and :LiveShareName
-- changes it. The plugin reads vim.g.live_share_username whenever it sends it.
local file = vim.fn.stdpath "state" .. "/live-share-name"

local function save(name)
  name = vim.trim(name or "")
  if name == "" then
    return
  end
  vim.fn.writefile({ name }, file)
  vim.g.live_share_username = name
  vim.notify("Live Share name: " .. name, vim.log.levels.INFO, { title = "Live Share" })
  return name
end

-- Offers the git name and the login name, or one typed in; then `done(name)`
local function pick(done)
  local current = vim.g.live_share_username
  local choices = {}
  for _, name in ipairs {
    current or "", -- nil would end the list early
    vim.trim(vim.fn.system { "git", "config", "--global", "user.name" }),
    vim.uv.os_get_passwd().username,
  } do
    if name and name ~= "" and not vim.tbl_contains(choices, name) then
      choices[#choices + 1] = name
    end
  end
  choices[#choices + 1] = "Other…"
  vim.ui.select(choices, { prompt = "Live Share name (shown to peers)" }, function(choice)
    if choice == "Other…" then
      vim.ui.input({ prompt = "Live Share name: ", default = current }, function(name)
        done(save(name))
      end)
    elseif choice then
      done(save(choice))
    else
      done()
    end
  end)
end

return {
  "azratul/live-share.nvim",
  cmd = {
    "LiveShareHostStart", "LiveShareJoin", "LiveShareStop", "LiveShareServer", "LiveShareOpen",
    "LiveShareFollow", "LiveShareUnfollow", "LiveSharePeers", "LiveShareTerminal", "LiveShareWorkspace",
    "LiveShareDebugInfo",
  },
  init = function()
    local saved = vim.fn.filereadable(file) == 1 and vim.fn.readfile(file)[1]
    if saved and saved ~= "" then
      vim.g.live_share_username = saved
    end
    vim.api.nvim_create_user_command("LiveShareName", function(opts)
      if opts.args ~= "" then
        save(opts.args)
      else
        pick(function() end)
      end
    end, { nargs = "?", desc = "Set the name Live Share peers see" })
  end,
  config = function(_, opts)
    require("live-share").setup(opts)
    -- No name yet: ask before hosting or joining, then carry on
    local commands = require "live-share.commands"
    for _, key in ipairs { "host_start", "join" } do
      local run = commands[key]
      commands[key] = function(...)
        if vim.g.live_share_username then
          return run(...)
        end
        local args = { ... }
        pick(function(name)
          if name then
            run(unpack(args))
          end
        end)
      end
    end
  end,
}
