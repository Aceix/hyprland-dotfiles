-- "Add Dev Container Configuration…": VS Code's flow, in pickers. Template →
-- its options → features → confirm → files written → devcontainer.json opened
-- (jsonls + SchemaStore check it). Templates and features come from the
-- official catalog (catalog.lua); the template's comments are kept.
local core = require "devcontainer.core"
local project = require "devcontainer.project"
local catalog = require "devcontainer.catalog"

local M = {}

local MAIN = ".devcontainer/devcontainer.json"
-- The template's own metadata and docs, not project files
local SKIP = { ["devcontainer-template.json"] = true, ["README.md"] = true, ["NOTES.md"] = true }

-- ${templateOption:<id>} → its value, in any template file
function M.substitute(text, values)
  return (text:gsub("%${templateOption:([%w_%-]+)}", function(id)
    return values[id] ~= nil and tostring(values[id]) or ""
  end))
end

-- Template files and where they go: as listed, but a named config's
-- .devcontainer/* goes under .devcontainer/<name>/; optional paths
-- (.github/dependabot.yml, ...) are left out, as the CLI's --omit-paths does
function M.targets(meta, root, name)
  local function optional(rel)
    for _, p in ipairs(meta.optionalPaths or {}) do
      if rel == p or (p:sub(-2) == "/*" and rel:sub(1, #p - 1) == p:sub(1, -2)) then
        return true
      end
    end
  end
  local out = {}
  for _, rel in ipairs(meta.files or {}) do
    if not SKIP[rel] and not optional(rel) then
      local to = name and rel:gsub("^%.devcontainer/", ".devcontainer/" .. name .. "/") or rel
      out[#out + 1] = { rel = rel, to = to, path = root .. "/" .. to, main = rel == MAIN }
    end
  end
  return out
end

-- Adds `refs` (feature references) to a devcontainer.json's text, keeping its
-- comments and layout: into an existing "features" object, else as a new one
-- after the opening brace
function M.merge_features(text, refs)
  refs = vim.tbl_filter(function(r)
    return not text:find('"' .. r .. '"', 1, true)
  end, refs)
  if #refs == 0 then
    return text
  end
  local lines = vim.split(text, "\n", { plain = true })
  local unit = text:match "\n([ \t]+)%S" or "\t"
  local function code(i) -- line i, or nil when blank or a comment
    local l = lines[i]
    return l and not l:match "^%s*$" and not l:match "^%s*//" and l or nil
  end
  local function next_code(i)
    for j = i, #lines do
      if code(j) then
        return lines[j]
      end
    end
    return ""
  end
  local function entries(indent)
    return vim.tbl_map(function(r)
      return ('%s"%s": {}'):format(indent, r)
    end, refs)
  end
  local function join(list, last_comma)
    for k = 1, #list do
      if k < #list or last_comma then
        list[k] = list[k] .. ","
      end
    end
    return list
  end

  for i = 1, #lines do
    local pre, rest = (code(i) or ""):match '^(%s*)"features"%s*:%s*{(.*)$'
    if pre then
      local inner = pre .. unit
      local inline_empty = rest:match "^%s*}(.*)$"
      if inline_empty then -- "features": {},
        local block = join(entries(inner), false)
        lines[i] = pre .. '"features": {'
        table.insert(block, pre .. "}" .. inline_empty)
        for k = #block, 1, -1 do
          table.insert(lines, i + 1, block[k])
        end
      else
        local empty = next_code(i + 1):match "^%s*}"
        local block = join(entries(inner), not empty)
        for k = #block, 1, -1 do
          table.insert(lines, i + 1, block[k])
        end
      end
      return table.concat(lines, "\n")
    end
  end

  for i = 1, #lines do
    if code(i) and lines[i]:find("{", 1, true) then
      local indent = (lines[i + 1] or ""):match "^(%s+)" or unit
      local closing = next_code(i + 1):match "^%s*}" and "}" or "},"
      local block = join(entries(indent .. unit), false)
      table.insert(block, 1, indent .. '"features": {')
      table.insert(block, indent .. closing)
      for k = #block, 1, -1 do
        table.insert(lines, i + 1, block[k])
      end
      return table.concat(lines, "\n")
    end
  end
  return text
end

local function feature_ref(f)
  return catalog.FEATURE_REF:format(f.id, (f.version or "1"):match "^(%d+)" or "1")
end

local function write(path, text, mode)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
  if mode then
    vim.uv.fs_chmod(path, mode)
  end
end

-- Writes the template extracted in `dir` into `root`; returns the main
-- config's path, or nil, err (nothing is written when the result isn't valid)
function M.apply(dir, meta, root, values, refs, name)
  local files = {}
  for _, t in ipairs(M.targets(meta, root, name)) do
    local src = dir .. "/" .. t.rel
    local stat = vim.uv.fs_stat(src)
    if stat and stat.type == "file" then
      local f = assert(io.open(src, "rb"))
      local text = M.substitute(f:read "*a", values)
      f:close()
      if t.main then
        text = M.merge_features(text, refs)
        local ok, err = project.decode(text)
        if not ok then
          return nil, ("%s would be invalid: %s"):format(t.to, err)
        end
      end
      files[#files + 1] = { path = t.path, text = text, mode = stat.mode, main = t.main }
    end
  end
  local main
  for _, f in ipairs(files) do
    write(f.path, f.text, f.mode)
    main = f.main and f.path or main
  end
  return main
end

local function bundled_path(root, name)
  return ("%s/.devcontainer/%sdevcontainer.json"):format(root, name and (name .. "/") or "")
end

-- An offline, image-only config (catalog's bundled fallback)
local function apply_bundled(t, root, refs, name)
  local cfg = { name = name or vim.fs.basename(root), image = t.image }
  if #refs > 0 then
    cfg.features = {}
    for _, r in ipairs(refs) do
      cfg.features[r] = vim.empty_dict()
    end
  end
  local path = bundled_path(root, name)
  write(path, vim.json.encode(cfg, { indent = "  " }) .. "\n")
  return path
end

-- vim.ui.select as a callback chain that ends on cancel
local function select(items, prompt, format, cb)
  vim.ui.select(items, { prompt = prompt, format_item = format }, function(choice)
    if choice ~= nil then
      cb(choice)
    end
  end)
end

local function ask_options(t, cb)
  local ids = vim.tbl_keys(t.options or {})
  table.sort(ids)
  local values = {}
  for _, id in ipairs(ids) do
    values[id] = t.options[id].default
  end
  if #ids == 0 then
    return cb(values)
  end
  select({ "Use the defaults", "Choose options…" }, t.name .. " options", nil, function(how)
    if how == "Use the defaults" then
      return cb(values)
    end
    local function step(i)
      if i > #ids then
        return cb(values)
      end
      local id, opt = ids[i], t.options[ids[i]]
      local prompt = opt.description or id
      local choices = opt.enum or opt.proposals
      if opt.type == "boolean" then
        choices = { true, false }
      end
      if not choices then
        return vim.ui.input({ prompt = prompt .. " ", default = tostring(opt.default or "") }, function(v)
          if v then
            values[id] = v
            step(i + 1)
          end
        end)
      end
      local list = vim.deepcopy(choices)
      if opt.proposals then
        list[#list + 1] = "Other…"
      end
      select(list, prompt, function(v)
        return tostring(v) .. (v == opt.default and "  (default)" or "")
      end, function(v)
        if v == "Other…" then
          return vim.ui.input({ prompt = prompt .. " ", default = tostring(opt.default or "") }, function(typed)
            if typed then
              values[id] = typed
              step(i + 1)
            end
          end)
        end
        values[id] = v
        step(i + 1)
      end)
    end
    step(1)
  end)
end

-- Multi-select by toggling: pick a feature to add/remove, "Done" to finish
local function ask_features(cb)
  catalog.collection("features", function(features, note)
    if note then
      core.notify(note, vim.log.levels.WARN)
    end
    if #features == 0 then
      return cb {}
    end
    table.sort(features, function(a, b)
      return a.name < b.name
    end)
    local picked = {}
    local function loop()
      local n = vim.tbl_count(picked)
      local items = vim.list_extend({ { done = true } }, features)
      select(items, "Features (pick to toggle)", function(f)
        if f.done then
          return ("✔ Done — %d selected"):format(n)
        end
        return ("%s %s — %s"):format(picked[f.id] and "[x]" or "[ ]", f.name, f.description or "")
      end, function(f)
        if f.done then
          local refs = {}
          for _, feat in ipairs(features) do
            if picked[feat.id] then
              refs[#refs + 1] = feature_ref(feat)
            end
          end
          return cb(refs)
        end
        picked[f.id] = not picked[f.id] or nil
        loop()
      end)
    end
    loop()
  end)
end

local function finish(path, root)
  project.forget()
  vim.cmd.edit(vim.fn.fnameescape(path))
  core.notify(
    ("Created %s.\n<leader>rD → Reopen in Container"):format(vim.fn.fnamemodify(path, ":~:."))
      .. (root ~= vim.uv.cwd() and ("\n(project root: %s)"):format(vim.fn.fnamemodify(root, ":~")) or "")
  )
end

local function confirm(root, targets)
  local lines = vim.tbl_map(function(t)
    return ("  %s%s"):format(t.to, vim.uv.fs_stat(t.path) and "  (replace)" or "")
  end, targets)
  return vim.fn.confirm(
    ("Write to %s:\n%s"):format(vim.fn.fnamemodify(root, ":~"), table.concat(lines, "\n")),
    "&Write\n&Cancel",
    1
  ) == 1
end

local function create(root, name, t, values, refs)
  local main = bundled_path(root, name)
  local targets = t.bundled and { { to = main:sub(#root + 2), path = main } } or M.targets(t, root, name)
  if not confirm(root, targets) then
    return
  end
  if t.bundled then
    return finish(apply_bundled(t, root, refs, name), root)
  end
  core.notify(("Fetching the %s template…"):format(t.name))
  catalog.template(t.id, function(dir, err)
    if not dir then
      return core.notify("Couldn't fetch the template: " .. err, vim.log.levels.ERROR)
    end
    local path, apply_err = M.apply(dir, t, root, values, refs, name)
    vim.fn.delete(dir, "rf")
    if not path then
      return core.notify(apply_err or "The template has no devcontainer.json", vim.log.levels.ERROR)
    end
    finish(path, root)
  end)
end

function M.run()
  local root = project.root() or vim.uv.cwd()
  local existing = project.configs(root)

  local function with_template(name)
    catalog.collection("templates", function(templates, note)
      if note then
        core.notify(note, vim.log.levels.WARN)
      end
      table.sort(templates, function(a, b)
        return a.name < b.name
      end)
      select(templates, "Dev Container template", function(t)
        return ("%s — %s"):format(t.name, t.description or "")
      end, function(t)
        local function go(n)
          ask_options(t, function(values)
            ask_features(function(refs)
              create(root, n, t, values, refs)
            end)
          end)
        end
        if name ~= true then
          return go(name)
        end
        vim.ui.input({ prompt = "Configuration name: ", default = t.id }, function(n)
          n = n and vim.trim(n):gsub("[^%w._-]", "-")
          if n and n ~= "" then
            go(n)
          end
        end)
      end)
    end)
  end

  if #existing == 0 then
    return with_template(nil)
  end
  select(
    { "Add a named configuration (.devcontainer/<name>/)", "Replace the default configuration" },
    ("%s already has a configuration"):format(vim.fs.basename(root)),
    nil,
    function(how)
      with_template(how:find("^Add") and true or nil)
    end
  )
end

return M
