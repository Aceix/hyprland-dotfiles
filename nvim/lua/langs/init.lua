-- Languages whose tooling is set up the first time one of their files is
-- opened, never at startup: language server, Mason packages, treesitter
-- parsers, formatters, linters, debugger, test adapters. One file each,
-- lua/langs/<name>.lua, returning any of:
--
--   mason   = { "pkg", { "pkg", needs = "node" } }   installed on first use
--   lsp     = { server = { ...overrides } }          vim.lsp.config + enable
--   parsers = { "lang" }                             treesitter, built if missing
--   format  = { ft = { "formatter" } }               conform (<leader>cf)
--   lint    = { ft = { "linter" } }                  nvim-lint
--   dap     = function(dap) end                      adapters / configurations
--   neotest = { detect = fn(cwd), adapters = fn() }  test adapters
--   deps    = function(d) return { test = {}, debug = {} } end   utils/deps.lua
--
-- and listed in `index` below, the only part read at startup. (Go, JS/TS,
-- Python, Java, Dart and Lua predate this and live in configs/*.lua.)
local M = {}

-- name -> filetypes that switch it on, test-file globs that load neotest
M.index = {
  php = { ft = { "php", "blade" }, tests = { "*Test.php", "*/tests/*.php" } },
  rust = { ft = { "rust" }, tests = { "*/tests/*.rs" } },
  shell = { ft = { "sh", "bash" } },
  docker = { ft = { "dockerfile", "yaml.docker-compose" } },
  sql = { ft = { "sql", "mysql", "plsql" } },
}

local active = {}

function M.spec(name)
  return require("langs." .. name)
end

-- Every language's value for `field`, for the configs that are themselves
-- loaded on demand (conform, nvim-lint, dap, deps)
local function each(field)
  local out = {}
  for name in pairs(M.index) do
    out[name] = M.spec(name)[field]
  end
  return out
end

local function by_ft(field)
  local out = {}
  for _, tbl in pairs(each(field)) do
    for ft, tools in pairs(tbl) do
      out[ft] = tools
    end
  end
  return out
end

function M.formatters()
  return by_ft "format"
end

function M.linters()
  return by_ft "lint"
end

function M.apply_dap(dap)
  for _, setup in pairs(each "dap") do
    setup(dap)
  end
end

function M.deps(builders)
  local out = { test = {}, debug = {} }
  for _, deps in pairs(each "deps") do
    for kind, entries in pairs(deps(builders)) do
      for key, entry in pairs(entries) do
        out[kind][key] = entry
      end
    end
  end
  return out
end

-- neotest fixes its adapters when it's set up: those of the languages already
-- opened this session or found in the project. One opened later needs
-- `:Lazy reload neotest`.
function M.neotest_adapters()
  local cwd = vim.uv.cwd()
  local out = {}
  for name in pairs(M.index) do
    local neotest = M.spec(name).neotest
    if neotest and (active[name] or neotest.detect(cwd)) then
      vim.list_extend(out, neotest.adapters())
    end
  end
  return out
end

function M.test_patterns()
  local out = {}
  for _, entry in pairs(M.index) do
    vim.list_extend(out, entry.tests or {})
  end
  return out
end

local function buffers(name)
  return vim.tbl_filter(function(buf)
    return vim.api.nvim_buf_is_loaded(buf) and vim.tbl_contains(M.index[name].ft, vim.bo[buf].filetype)
  end, vim.api.nvim_list_bufs())
end

function M.activate(name)
  if active[name] then
    return
  end
  active[name] = true
  local spec = M.spec(name)

  require("utils.mason_ensure").ensure(spec.mason, function()
    for server, overrides in pairs(spec.lsp or {}) do
      if next(overrides) then
        vim.lsp.config(server, overrides)
      end
      -- (attaches to the buffers already open, too)
      vim.lsp.enable(server)
    end
    if spec.lint then
      require("lazy").load { plugins = { "nvim-lint" } }
    end
  end)

  -- NvChad's FileType autocmd found no parser to start; start it once built
  require("utils.ts_parsers").ensure(spec.parsers, function()
    for _, buf in ipairs(buffers(name)) do
      pcall(vim.treesitter.start, buf)
    end
  end)
end

function M.setup()
  local by_filetype, patterns = {}, {}
  for name, entry in pairs(M.index) do
    for _, ft in ipairs(entry.ft) do
      by_filetype[ft] = name
      patterns[#patterns + 1] = ft
    end
  end
  vim.api.nvim_create_autocmd("FileType", {
    group = vim.api.nvim_create_augroup("Langs", { clear = true }),
    pattern = patterns,
    callback = function(ev)
      M.activate(by_filetype[ev.match])
    end,
  })
end

return M
