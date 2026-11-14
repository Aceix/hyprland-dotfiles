-- Treesitter parsers wherever this config runs, remotes and containers
-- included. nvim-treesitter `main` builds parsers with the `tree-sitter` CLI
-- and a C compiler; a fresh remote has no parsers (they live in data/, which
-- remote-nvim doesn't copy wholesale) and usually no CLI. So:
--
--  * a Linux machine copies its built parsers (data/site) to remotes on the
--    same OS and CPU (configs/remote-nvim.lua, utils/remote.lua). They need
--    only glibc 2.14, so they load in nearly any Linux container or host.
--  * ensure() repairs the query links that copy leaves pointing at this
--    machine's plugin dir, drops parsers that don't load there, and builds
--    whatever is still missing.
--  * no `tree-sitter` on PATH: a pinned release goes into data/bin, checked
--    against GitHub's sha256. Where it can't run (glibc < 2.39, musl) or
--    there's no C compiler, one hint replaces a wall of build errors.
local M = {}

local CLI_VERSION = "0.26.9"
-- tree-sitter-<platform>.gz → sha256, from the GitHub release's asset digests
local CLI_SHA256 = {
  ["linux-x64"] = "9ce82137caa65864e7ca8b869fd391cef88c9bd2a01c4371b9c4dd26c2585efb",
  ["linux-arm64"] = "c8feeb32115958cb44442ca4d68f6d66cf7605dbd65681e62342181ebdd6db3b",
  ["macos-x64"] = "a57b6044ad739ca3164cc20637db65352ccc9c69e1c34a7cda3e5a62d529b164",
  ["macos-arm64"] = "e46725b2417c085b0761948abc0cc240bff6a3ab5d2128e3ad0de467ded3388d",
}

-- the private CLI's folder
M.BIN = vim.fn.stdpath "data" .. "/bin"

-- "linux-x64" / "macos-arm64" / ..., for this machine or for `uname -s -m`
-- values (remote-nvim stores "Linux"/"macOS" and the machine); nil if unknown
function M.platform(sysname, machine)
  if not sysname then
    local u = vim.uv.os_uname()
    sysname, machine = u.sysname, u.machine
  end
  local os = ({ Linux = "linux", Darwin = "macos", macOS = "macos" })[sysname]
  local arch = ({ x86_64 = "x64", amd64 = "x64", aarch64 = "arm64", arm64 = "arm64" })[machine]
  return os and arch and (os .. "-" .. arch) or nil
end

local function runs(cmd)
  local ok, proc = pcall(vim.system, { cmd, "--version" }, { text = true })
  local out = ok and proc:wait(5000)
  return out and out.code == 0
end

local function has_compiler()
  for _, cc in ipairs { vim.env.CC or "cc", "gcc", "clang" } do
    if vim.fn.executable(cc) == 1 then
      return true
    end
  end
end

-- `tree-sitter` on PATH for this Neovim (and the builds it starts):
-- cb(true), or cb(false, why)
local function ensure_cli(cb)
  if vim.fn.executable "tree-sitter" == 1 then
    return cb(true)
  end
  local private = M.BIN .. "/tree-sitter"
  local function use()
    vim.env.PATH = M.BIN .. ":" .. vim.env.PATH
    cb(true)
  end
  if vim.uv.fs_stat(private) and runs(private) then
    return use()
  end
  local platform = M.platform()
  local sha256 = platform and CLI_SHA256[platform]
  if not sha256 then
    return cb(false, "no tree-sitter release for this platform")
  end
  vim.fn.mkdir(M.BIN, "p")
  local gz = private .. ".gz"
  local url = ("https://github.com/tree-sitter/tree-sitter/releases/download/v%s/tree-sitter-%s.gz"):format(
    CLI_VERSION,
    platform
  )
  local run = require("devcontainer.core").run
  run({ "curl", "-fsSL", "--max-time", "120", "-o", gz, url }, function(dl)
    local f = dl.code == 0 and io.open(gz, "rb")
    local data = f and f:read "*a"
    if f then
      f:close()
    end
    if not data or vim.fn.sha256(data) ~= sha256 then
      os.remove(gz)
      return cb(false, data and "the tree-sitter download didn't match its checksum" or "couldn't download tree-sitter")
    end
    run({ "gzip", "-df", gz }, function(unpack)
      if unpack.code ~= 0 then
        return cb(false, "couldn't unpack tree-sitter")
      end
      vim.uv.fs_chmod(private, tonumber("755", 8))
      if not runs(private) then
        os.remove(private)
        return cb(false, "the tree-sitter release doesn't run here (it needs glibc 2.39+)")
      end
      use()
    end)
  end)
end

-- Copied query dirs are links into the other machine's plugin: point them at
-- this one's (what nvim-treesitter's own install links them to)
local function repair_query_links()
  local install = require "nvim-treesitter.install"
  local dir = require("nvim-treesitter.config").get_install_dir "queries"
  for name, kind in vim.fs.dir(dir) do
    local link = dir .. "/" .. name
    if kind == "link" and not vim.uv.fs_realpath(link) then
      os.remove(link)
      local src = install.get_package_path("runtime", "queries", name)
      if vim.uv.fs_stat(src) then
        vim.uv.fs_symlink(src, link, { dir = true })
      end
    end
  end
end

-- Parsers that don't load here (copied from another CPU, or needing a newer
-- libc) are removed, so they get built instead
local function drop_broken(installed)
  local config = require "nvim-treesitter.config"
  return vim.tbl_filter(function(lang)
    local ok, loaded = pcall(vim.treesitter.language.add, lang)
    if ok and loaded then
      return true
    end
    os.remove(config.get_install_dir "parser" .. "/" .. lang .. ".so")
    os.remove(config.get_install_dir "parser-info" .. "/" .. lang .. ".revision")
    return false
  end, installed)
end

-- Builds the parsers in `wanted` that are missing (filetype aliases resolve to
-- the parser behind them: `jsonc` is `json`). A no-op once all are there.
function M.ensure(wanted)
  local ts = require "nvim-treesitter"
  local remote = require("utils.remote").is_remote
  if remote then
    repair_query_links()
  end
  local installed = ts.get_installed "parsers"
  if remote then
    installed = drop_broken(installed)
  end

  local need, seen = {}, {}
  for _, lang in ipairs(wanted or {}) do
    local parser = vim.treesitter.language.get_lang(lang) or lang
    if not seen[parser] and not vim.tbl_contains(installed, parser) then
      seen[parser] = true
      need[#need + 1] = parser
    end
  end
  if #need == 0 then
    return
  end

  local function hint(why)
    vim.notify(
      ("[treesitter] %d parser(s) can't be built here (%s): %s"):format(#need, why, table.concat(need, ", ")),
      vim.log.levels.WARN
    )
  end
  if not has_compiler() then
    return hint "no C compiler"
  end
  ensure_cli(function(ok, why)
    if not ok then
      return hint(why)
    end
    vim.notify(("[treesitter] building %d missing parser(s): %s"):format(#need, table.concat(need, ", ")))
    -- force: nvim-treesitter counts a language whose queries are there as
    -- installed, so a missing (or dropped) parser with copied queries would
    -- be skipped; `need` only holds parsers that really aren't there
    ts.install(need, { force = true, summary = true })
  end)
end

-- lazy.nvim's build step for nvim-treesitter: :TSUpdate, once the CLI is
-- there (fetched as above). Without one it does nothing; ensure() then says
-- which parsers can't be built.
function M.update()
  ensure_cli(function(ok)
    if ok then
      require("nvim-treesitter").update(nil, { summary = true })
    end
  end)
end

return M
