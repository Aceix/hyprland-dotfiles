-- VS Code's Explorer context menu for nvim-tree, drawn with nvzone/menu.
-- Right-click a node (any window, see M.right_click) or press Shift+F10 in the
-- tree; files and folders get different items, in VS Code's order. The
-- right-hand hints are nvim-tree's own keys, which also pick the item while
-- the menu is open from the keyboard.
local M = {}

local api = vim.api
local tree = function()
  return require "nvim-tree.api"
end

-- Path picked with "Select for Compare", kept like VS Code's
local compare_base

-- The parent of a file, or a folder itself
local function dir_of(t)
  return t.is_dir and t.path or vim.fs.dirname(t.path)
end

local function new_folder(t)
  vim.ui.input({ prompt = "New folder: " }, function(name)
    name = name and vim.trim(name) or ""
    if name == "" then
      return
    end
    local path = vim.fs.joinpath(dir_of(t), name)
    if vim.uv.fs_stat(path) then
      return vim.notify(path .. " already exists", vim.log.levels.WARN)
    end
    vim.fn.mkdir(path, "p")
    tree().tree.reload()
    pcall(tree().tree.find_file, { buf = path, focus = true })
  end)
end

-- The system file manager with the node selected; just the folder when no
-- file manager implements org.freedesktop.FileManager1
local function reveal(t)
  vim.system({
    "gdbus", "call", "--session",
    "--dest", "org.freedesktop.FileManager1",
    "--object-path", "/org/freedesktop/FileManager1",
    "--method", "org.freedesktop.FileManager1.ShowItems",
    "['" .. vim.uri_from_fname(t.path) .. "']", "",
  }, {}, function(res)
    if res.code ~= 0 then
      vim.schedule(function()
        vim.ui.open(vim.fs.dirname(t.path))
      end)
    end
  end)
end

local function compare(t)
  vim.cmd.tabnew(vim.fn.fnameescape(compare_base))
  vim.cmd("vertical diffsplit " .. vim.fn.fnameescape(t.path))
end

local sep = { name = "separator" }

--- Menu items for target `t` ({ node, path, is_dir, is_root }).
local function items(t)
  local fs, node = tree().fs, t.node
  local in_git = vim.fs.root(t.path, ".git") ~= nil
  local list = {}
  local function add(...)
    vim.list_extend(list, { ... })
  end

  if t.is_dir then
    add(
      { name = "  New File...", rtxt = "a", cmd = function() fs.create(node) end },
      { name = "  New Folder...", cmd = function() new_folder(t) end },
      sep
    )
  else
    add(
      { name = "  Open", rtxt = "o", cmd = function() tree().node.open.edit(node) end },
      { name = "  Open to the Side", rtxt = "<C-v>", cmd = function() tree().node.open.vertical(node) end },
      { name = "  Open With Default App", rtxt = "s", cmd = function() vim.ui.open(t.path) end }
    )
  end
  add(
    { name = "  Reveal in File Manager", cmd = function() reveal(t) end },
    { name = "  Open in Integrated Terminal", cmd = function() require("utils.term").new(dir_of(t)) end },
    sep
  )

  if t.is_dir then
    add({
      name = "  Find in Folder...",
      cmd = function()
        -- grug-far splits its paths field on spaces; "\\ " keeps one
        require("grug-far").open { prefills = { paths = (t.path:gsub(" ", "\\ ")) } }
      end,
    }, sep)
  else
    add({
      name = "  Select for Compare",
      cmd = function()
        compare_base = t.path
      end,
    })
    if compare_base and compare_base ~= t.path then
      add({
        name = "  Compare with Selected",
        cmd = function()
          compare(t)
        end,
      })
    end
    add(sep)
  end

  if in_git then
    local arg = vim.fn.fnameescape(t.path)
    add(
      { name = "  Open Changes", cmd = "DiffviewOpen -- " .. arg },
      { name = "  Open Timeline", cmd = "DiffviewFileHistory " .. arg },
      sep
    )
  end

  if not t.is_root then
    add(
      { name = "  Cut", rtxt = "x", cmd = function() fs.cut(node) end },
      { name = "  Copy", rtxt = "c", cmd = function() fs.copy.node(node) end }
    )
  end
  if t.is_dir then
    add({ name = "  Paste", rtxt = "p", cmd = require("configs.nvim-tree").paste })
  end
  add(
    sep,
    { name = "󰴠  Copy Path", rtxt = "gy", cmd = function() fs.copy.absolute_path(node) end },
    { name = "  Copy Relative Path", rtxt = "Y", cmd = function() fs.copy.relative_path(node) end },
    sep,
    {
      name = "  Run Tests",
      cmd = function()
        require("neotest").run.run(t.path)
      end,
    }
  )

  if not t.is_root then
    add(
      sep,
      { name = "  Rename...", rtxt = "r", cmd = function() fs.rename(node) end },
      { name = "  Delete", rtxt = "D", cmd = function() fs.trash(node) end },
      { name = "  Delete Permanently", hl = "ExRed", rtxt = "d", cmd = function() fs.remove(node) end }
    )
  end

  -- no leading / trailing / doubled separators from the skipped groups
  local out = {}
  for _, item in ipairs(list) do
    if item ~= sep or (#out > 0 and out[#out] ~= sep) then
      table.insert(out, item)
    end
  end
  if out[#out] == sep then
    table.remove(out)
  end
  return out
end

--- Open the menu for the node under the cursor in the tree window, or for
--- the tree's root folder with `opts.root`.
---@param opts? { mouse?: boolean, root?: boolean }
function M.open(opts)
  opts = opts or {}
  local root = tree().tree.get_nodes()
  local node = not opts.root and tree().tree.get_node_under_cursor() or nil
  -- the root's header line, or ".." when that's shown
  local is_root = not node or node.name == ".." or node.absolute_path == root.absolute_path
  if is_root then
    node = root
  end
  local t = { node = node, path = node.absolute_path, is_dir = node.type == "directory", is_root = is_root }

  require("menu.utils").delete_old_menus()
  require("menu").open(items(t), { mouse = opts.mouse })
end

--- <RightMouse> expr handler: on an nvim-tree window, move the cursor to the
--- clicked node and open the menu there (the root folder's, on the empty space
--- below the last node, like VS Code); anywhere else, the normal right-click.
function M.right_click()
  local pos = vim.fn.getmousepos()
  if pos.winid == 0 or vim.bo[api.nvim_win_get_buf(pos.winid)].filetype ~= "NvimTree" then
    return "<RightMouse>"
  end
  local blank = pos.line == 0 -- getmousepos() gives 0 past the last line
  vim.schedule(function()
    M.open { mouse = true, root = blank }
  end)
  return "<LeftMouse>"
end

return M
