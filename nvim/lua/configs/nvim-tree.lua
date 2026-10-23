local M = {}

-- `p`: if the clipboard holds an image, save it (via img-clip) into the
-- directory under the cursor, prompting for a name; otherwise fall back to
-- nvim-tree's normal paste of copied/cut nodes.
local function paste_image_or_node()
  local api = require "nvim-tree.api"
  require "img-clip" -- loads the plugin so its config is set up
  local clipboard = require "img-clip.clipboard"
  if not clipboard.get_clip_cmd() or not clipboard.content_is_image() then
    return api.fs.paste()
  end

  local node = api.tree.get_node_under_cursor()
  local dir
  if not node or node.name == ".." then
    dir = require("nvim-tree.core").get_cwd()
  elseif node.type == "directory" then
    dir = node.absolute_path
  else
    dir = vim.fn.fnamemodify(node.absolute_path, ":h")
  end

  vim.ui.input({ prompt = "Image name: ", default = os.date "%Y-%m-%d-%H-%M-%S" }, function(name)
    if not name or vim.trim(name) == "" then
      return
    end
    name = vim.trim(name)
    local ext = vim.fn.fnamemodify(name, ":e"):lower()
    if ext == "" then
      ext, name = "png", name .. ".png"
    end
    -- The clipboard only ever yields PNG; other extensions are converted
    -- with ImageMagick, or fall back to .png if it isn't installed.
    if ext ~= "png" and vim.fn.executable "magick" == 0 then
      vim.notify(
        "ImageMagick (`magick`) not installed; can't convert to ." .. ext .. ", saving as .png",
        vim.log.levels.WARN
      )
      ext, name = "png", vim.fn.fnamemodify(name, ":r") .. ".png"
    end
    -- magick silently writes PNG for extensions it doesn't know, so check
    -- that it lists the format as writable first
    if ext ~= "png" then
      local formats = vim.system({ "magick", "-list", "format" }):wait().stdout or ""
      local writable = vim.iter(vim.gsplit(formats, "\n")):any(function(line)
        local fmt, mode = line:match "^%s*(%S-)%*?%s+%S+%s+(%S+)"
        return fmt and fmt:lower() == ext and mode:find "w" ~= nil
      end)
      if not writable then
        return vim.notify("ImageMagick can't write ." .. ext .. " images", vim.log.levels.ERROR)
      end
    end
    local path = vim.fs.joinpath(dir, name)
    if vim.uv.fs_stat(path) then
      return vim.notify(path .. " already exists", vim.log.levels.WARN)
    end
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local png = ext == "png" and path or vim.fn.tempname() .. ".png"
    if not clipboard.save_image(png) then
      return vim.notify("Failed to save image to " .. path, vim.log.levels.ERROR)
    end
    if png ~= path then
      local res = vim.system({ "magick", png, path }):wait()
      os.remove(png)
      if res.code ~= 0 then
        return vim.notify("Failed to convert image to ." .. ext .. ": " .. res.stderr, vim.log.levels.ERROR)
      end
    end
    api.tree.reload()
    api.tree.find_file { buf = path, focus = true }
  end)
end

local function on_attach(bufnr)
  local api = require "nvim-tree.api"
  api.config.mappings.default_on_attach(bufnr)
  vim.keymap.set("n", "p", paste_image_or_node, {
    buffer = bufnr,
    noremap = true,
    silent = true,
    nowait = true,
    desc = "nvim-tree: Paste image or node",
  })
  -- VS Code's context menu from the keyboard (utils/tree_menu.lua); many
  -- terminals send Shift+F10 as <F22>
  for _, lhs in ipairs { "<S-F10>", "<F22>" } do
    vim.keymap.set("n", lhs, function()
      require("utils.tree_menu").open()
    end, { buffer = bufnr, desc = "nvim-tree: Context menu" })
  end
end

M.paste = paste_image_or_node

M.opts = function(_, opts)
  opts.on_attach = on_attach

  opts.filters = opts.filters or {}

  opts.filters.dotfiles = false
  opts.filters.git_ignored = false

  -- Revealing the focused file is done in M.config, which skips dependency
  -- and outside-cwd files; nvim-tree's own would also reveal on open/toggle
  opts.update_focused_file = { enable = false }

  -- The side bar's width (utils/git_sidebar.lua), which nvim-tree resizes to
  -- on open and on opening a file; NvChad's fixed 30 reset a resized Explorer
  opts.view = opts.view or {}
  opts.view.width = require("utils.git_sidebar").width

  opts.renderer = opts.renderer or {}
  opts.renderer.highlight_git = "name"
  opts.renderer.group_empty = true -- VS Code-style compact folders
  opts.renderer.icons = opts.renderer.icons or {}
  opts.renderer.icons.show = opts.renderer.icons.show or {}
  opts.renderer.icons.show.git = false

  -- LSP errors/warnings should win over a plain git status color when a
  -- file has both. `renderer.decorators` already orders "Diagnostics"
  -- after "Git" by default, so later-wins name-highlight combining
  -- (nvim-tree/renderer/builder.lua) picks diagnostics automatically --
  -- it's just off by default (diagnostics.enable = false, and
  -- highlight_diagnostics = "none" so even when enabled it never
  -- touched the filename color).
  opts.diagnostics = opts.diagnostics or {}
  opts.diagnostics.enable = true
  opts.renderer.highlight_diagnostics = "name"

  return opts
end

M.config = function(_, opts)
  require("nvim-tree").setup(opts)

  -- Follow the focused file like VS Code, except files in dependency folders
  -- or outside the cwd (utils/dep_dirs.lua): a go-to-definition into
  -- node_modules shouldn't unfold it. <leader>E reveals one explicitly.
  local api = require "nvim-tree.api"
  local function reveal(buf)
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].buftype == "" and name ~= "" and not require("utils.dep_dirs").is_external(name) then
      api.tree.find_file { buf = buf }
    end
  end
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(ev)
      reveal(ev.buf)
    end,
  })
  -- Unless opened unfocused, the tree's window is current here; the file is
  -- in the one it opened from
  api.events.subscribe(api.events.Event.TreeOpen, function()
    local win = vim.bo.filetype == "NvimTree" and vim.fn.win_getid(vim.fn.winnr "#") or 0
    if vim.api.nvim_win_is_valid(win) or win == 0 then
      reveal(vim.api.nvim_win_get_buf(win))
    end
  end)

  -- Staged/Merge/Renamed file-status colors, kept off red/yellow (see
  -- chadrc.lua's base46.hl_override for Dirty/New/Deleted/Ignored).
  -- These 3 can't go through hl_override: nvim-tree resolves them to
  -- NvimTreeGit{Staged,Merge,Renamed}Icon -> generic theme groups
  -- (Constant/PreProc), and base46 only overrides keys it predefines
  -- itself, which doesn't include those Icon groups. Set them directly
  -- instead, and redo it after every theme switch (NvThemeReload) since
  -- that recompiles highlights and would otherwise wipe this out.
  local function set_git_hl()
    vim.api.nvim_set_hl(0, "NvimTreeGitStagedIcon", { fg = "#569CD6" }) -- blue: staged
    vim.api.nvim_set_hl(0, "NvimTreeGitMergeIcon", { fg = "#BB9AF7" }) -- purple: merge conflict
    vim.api.nvim_set_hl(0, "NvimTreeGitRenamedIcon", { fg = "#89DDFF" }) -- sky blue: renamed
  end
  set_git_hl()
  vim.api.nvim_create_autocmd("User", { pattern = "NvThemeReload", callback = set_git_hl })
end

return M
