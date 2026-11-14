-- The official Dev Container templates and features, as VS Code lists them:
-- OCI artifacts on ghcr.io, fetched with curl (anonymous token → manifest →
-- the one layer), each layer checked against its sha256 digest. No Node, no
-- devcontainer CLI. The two catalogs are cached for a day; offline, a stale
-- cache is used, then a few bundled base images.
local core = require "devcontainer.core"

local M = {}

local REGISTRY = "https://ghcr.io"
local CACHE = vim.fn.stdpath "cache" .. "/devcontainer"
local TTL = 24 * 3600

M.FEATURE_REF = "ghcr.io/devcontainers/features/%s:%s"

-- Offline fallback: image-only configs, written directly (no template files)
local BUNDLED = {
  { id = "ubuntu", name = "Ubuntu", image = "mcr.microsoft.com/devcontainers/base:ubuntu" },
  { id = "debian", name = "Debian", image = "mcr.microsoft.com/devcontainers/base:debian" },
  { id = "alpine", name = "Alpine", image = "mcr.microsoft.com/devcontainers/base:alpine" },
  { id = "python", name = "Python 3", image = "mcr.microsoft.com/devcontainers/python:3" },
  { id = "javascript-node", name = "Node.js", image = "mcr.microsoft.com/devcontainers/javascript-node:22" },
  { id = "go", name = "Go", image = "mcr.microsoft.com/devcontainers/go:1" },
  { id = "rust", name = "Rust", image = "mcr.microsoft.com/devcontainers/rust:1" },
}
for _, t in ipairs(BUNDLED) do
  t.bundled = true
  t.description = "Offline fallback: " .. t.image
end

local function curl(args, cb)
  core.run(vim.list_extend({ "curl", "-fsSL", "--max-time", "30" }, args), cb)
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read "*a"
  f:close()
  return data
end

-- Downloads the single layer of `repo` (e.g. "devcontainers/templates/go")
-- to `dest`; cb(dest) or cb(nil, err)
local function pull(repo, dest, cb)
  curl({ ("%s/token?scope=repository:%s:pull"):format(REGISTRY, repo) }, function(out)
    local ok, tok = pcall(vim.json.decode, out.stdout or "")
    tok = out.code == 0 and ok and type(tok) == "table" and tok.token
    if not tok then
      return cb(nil, "couldn't reach ghcr.io")
    end
    local auth = "Authorization: Bearer " .. tok
    curl({
      "-H", auth, "-H", "Accept: application/vnd.oci.image.manifest.v1+json",
      ("%s/v2/%s/manifests/latest"):format(REGISTRY, repo),
    }, function(m)
      local ok2, manifest = pcall(vim.json.decode, m.stdout or "")
      local layer = m.code == 0 and ok2 and type(manifest) == "table" and manifest.layers and manifest.layers[1]
      if not layer then
        return cb(nil, "unexpected manifest for " .. repo)
      end
      curl({ "-H", auth, "-o", dest, ("%s/v2/%s/blobs/%s"):format(REGISTRY, repo, layer.digest) }, function(b)
        if b.code ~= 0 then
          return cb(nil, core.error_text(b))
        end
        if "sha256:" .. vim.fn.sha256(read(dest) or "") ~= layer.digest then
          os.remove(dest)
          return cb(nil, repo .. ": download doesn't match its digest")
        end
        cb(dest)
      end)
    end)
  end)
end

local function decode_list(path, kind)
  local ok, data = pcall(vim.json.decode, read(path) or "")
  return ok and type(data) == "table" and type(data[kind]) == "table" and data[kind] or nil
end

-- cb(list, note): kind is "templates" or "features"; note says when the
-- list is stale or the bundled fallback
function M.collection(kind, cb)
  local path = ("%s/%s.json"):format(CACHE, kind)
  local stat = vim.uv.fs_stat(path)
  local cached = stat and decode_list(path, kind)
  if cached and os.time() - stat.mtime.sec < TTL then
    return cb(cached)
  end
  vim.fn.mkdir(CACHE, "p")
  local tmp = path .. ".part"
  pull("devcontainers/" .. kind, tmp, function(ok, err)
    local fresh = ok and decode_list(tmp, kind)
    if fresh then
      vim.uv.fs_rename(tmp, path)
      return cb(fresh)
    end
    os.remove(tmp)
    if cached then
      return cb(cached, ("Offline (%s): using the catalog from %s"):format(err, os.date("%x", stat.mtime.sec)))
    end
    cb(kind == "templates" and BUNDLED or {}, ("Offline (%s): only built-in base images"):format(err or "?"))
  end)
end

-- cb(dir) with the template's files extracted into a fresh temp dir, or cb(nil, err)
function M.template(id, cb)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  pull("devcontainers/templates/" .. id, dir .. ".tar", function(tar, err)
    if not tar then
      return cb(nil, err)
    end
    core.run({ "tar", "-xf", tar, "-C", dir }, function(out)
      os.remove(tar)
      if out.code ~= 0 then
        return cb(nil, core.error_text(out))
      end
      cb(dir)
    end)
  end)
end

return M
