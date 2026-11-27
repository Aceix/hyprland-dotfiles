-- Terminal provider for claudecode.nvim (plugins/claudecode.lua): Claude Code
-- runs as a "Claude" tab of the bottom panel (utils/term.lua) instead of in a
-- split of its own, and its tab goes when Claude exits.
local M = {}

local buf, job

local function term()
  return require "utils.term"
end

local function alive()
  return buf ~= nil and vim.api.nvim_buf_is_valid(buf) and job ~= nil and vim.fn.jobwait({ job }, 0)[1] == -1
end

local function show(focus)
  term().show(buf, { enter = focus })
  if focus then
    vim.cmd "startinsert"
  end
end

function M.setup() end

function M.is_available()
  return true
end

function M.open(cmd, env, config, focus)
  focus = focus ~= false
  if alive() then
    return show(focus)
  end
  buf = vim.api.nvim_create_buf(false, false)
  vim.bo[buf].bufhidden = "hide" -- survives the panel being toggled shut
  vim.b[buf].nvterm_label = "Claude"
  vim.api.nvim_buf_call(buf, function()
    job = vim.fn.jobstart(cmd, {
      term = true,
      cwd = config and config.cwd or nil,
      env = env and next(env) and env or nil,
    })
  end)
  show(focus)
end

function M.close()
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_delete(buf, { force = true })
  end
  buf, job = nil, nil
end

-- Show / hide, wherever the cursor is
function M.simple_toggle(cmd, env, config)
  if alive() and term().is_showing(buf) then
    term().hide()
  else
    M.open(cmd, env, config, true)
  end
end

-- Jump to Claude, or hide it when already in it
function M.focus_toggle(cmd, env, config)
  if alive() and term().is_showing(buf) and vim.api.nvim_get_current_buf() == buf then
    term().hide()
  else
    M.open(cmd, env, config, true)
  end
end

function M.get_active_bufnr()
  return alive() and buf or nil
end

return M
