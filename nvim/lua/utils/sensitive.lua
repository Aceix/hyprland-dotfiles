-- Files whose contents shouldn't leave the buffer: no swap, undo or backup
-- copies (options.lua), no local-history snapshots (plugins/file-history.lua)
-- and no completion, which would offer their words in other buffers.
local M = {}

M.patterns = { "*/.env", "*/.env.*", "*.pem", "*.key", "*/.ssh/*", "*/.aws/credentials", "*/.netrc" }

local regexes
function M.is(path)
  regexes = regexes or vim.tbl_map(function(glob)
    return vim.regex(vim.fn.glob2regpat(glob))
  end, M.patterns)
  for _, re in ipairs(regexes) do
    if re:match_str(path) then
      return true
    end
  end
  return false
end

local temp_dirs
--- Scratch files of other tools (git's COMMIT_EDITMSG aside): query buffers,
--- `$EDITOR` round-trips, ...
function M.is_temp(path)
  if not temp_dirs then
    temp_dirs = { "/tmp/", "/private/tmp/", "/var/folders/", "/private/var/folders/" }
    local tmp = vim.uv.os_tmpdir()
    if tmp then
      temp_dirs[#temp_dirs + 1] = vim.fs.normalize(tmp) .. "/"
    end
  end
  for _, dir in ipairs(temp_dirs) do
    if vim.startswith(path, dir) then
      return true
    end
  end
  return false
end

function M.setup()
  vim.opt.backupskip:append(M.patterns)
  vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
    group = vim.api.nvim_create_augroup("SensitiveFiles", { clear = true }),
    pattern = M.patterns,
    callback = function(ev)
      vim.bo[ev.buf].swapfile = false
      vim.bo[ev.buf].undofile = false
      vim.b[ev.buf].completion = false -- blink.cmp
    end,
  })
end

return M
