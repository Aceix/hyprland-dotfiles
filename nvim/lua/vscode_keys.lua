-- VS Code-style shortcuts layered on top of the Vim/NvChad keys. Only loaded
-- when settings.vscode_keys is true (see lua/mappings.lua). Vim modes stay;
-- where a VS Code key clashes with a Vim/NvChad default, VS Code wins, except
-- clipboard/undo keys, which only apply in insert and visual mode (normal-mode
-- <C-v>/<C-a>/<C-r> keep their Vim meaning; <C-q> is visual block too).
-- Multi-cursor (<C-d>, <C-S-l>, <C-S-Up/Down>) is in plugins/multicursor.lua,
-- debug F-keys in plugins/dap.lua.

local map = vim.keymap.set
local call = require "utils.call"
local niv = { "n", "i", "x" }

local function tele(picker, opts)
  return call("telescope.builtin", picker, opts)
end

local function selection()
  return table.concat(vim.fn.getregion(vim.fn.getpos "v", vim.fn.getpos ".", { type = vim.fn.mode() }), "\n")
end

-- NvChad maps normal <C-k> to "window up"; it would make the <C-k><C-i>
-- chord below wait 'timeoutlen'. Ctrl+Alt+Up still moves up a window.
pcall(vim.keymap.del, "n", "<C-k>")

-- === Navigation & LSP =======================================================
map({ "n", "i" }, "<C-p>", tele "find_files", { desc = "Quick Open (files)" })
map(niv, "<C-S-p>", tele "commands", { desc = "Command Palette" })
map(niv, "<F1>", tele "commands", { desc = "Command Palette" })
map("n", "<C-S-f>", tele "live_grep", { desc = "Search in files" })
map("x", "<C-S-f>", function()
  require("telescope.builtin").live_grep { default_text = selection() }
end, { desc = "Search selection in files" })

map("n", "<C-f>", "/", { desc = "Find in file" })
map("i", "<C-f>", "<Esc>/", { desc = "Find in file" })
map("x", "<C-f>", [["zy/\V<C-r>=escape(@z, '/\')<CR><CR>]], { desc = "Find selection in file" })

map("n", "<C-h>", function()
  require("grug-far").open { prefills = { search = vim.fn.expand "<cword>" } }
end, { desc = "Find & Replace" })
map("x", "<C-h>", call("grug-far", "with_visual_selection"), { desc = "Find & Replace selection" })

map({ "n", "i" }, "<C-g>", function()
  vim.ui.input({ prompt = "Go to line[:col]: " }, function(input)
    local line, col = (input or ""):match "^%s*(%d+)%s*:?%s*(%d*)"
    if line then
      line = math.min(tonumber(line), vim.api.nvim_buf_line_count(0))
      vim.api.nvim_win_set_cursor(0, { math.max(line, 1), math.max((tonumber(col) or 1) - 1, 0) })
      vim.cmd "normal! zz"
    end
  end)
end, { desc = "Go to Line" })

map({ "n", "i" }, "<C-S-o>", tele "lsp_document_symbols", { desc = "Go to Symbol in File" })
map("n", "<C-t>", tele "lsp_dynamic_workspace_symbols", { desc = "Go to Symbol in Workspace" })

map(niv, "<F12>", vim.lsp.buf.definition, { desc = "Go to Definition" })
map(niv, "<S-F12>", tele "lsp_references", { desc = "Find All References" })
map(niv, "<C-F12>", tele "lsp_implementations", { desc = "Go to Implementation" })
map(niv, "<F2>", vim.lsp.buf.rename, { desc = "Rename Symbol" })
map(niv, "<C-.>", vim.lsp.buf.code_action, { desc = "Quick Fix / Code Action" })
map("n", "<C-k><C-i>", vim.lsp.buf.hover, { desc = "Show Hover" })

map("n", "<F8>", function()
  vim.diagnostic.jump { count = 1, float = true }
end, { desc = "Next Problem" })
map("n", "<S-F8>", function()
  vim.diagnostic.jump { count = -1, float = true }
end, { desc = "Previous Problem" })

-- === Editing ================================================================
-- <C-/> under kitty's keyboard protocol, <C-_> in legacy terminals
for _, key in ipairs { "<C-/>", "<C-_>" } do
  map("n", key, "gcc", { remap = true, desc = "Toggle Line Comment" })
  map("x", key, "gcgv", { remap = true, desc = "Toggle Line Comment" })
  map("i", key, "<Cmd>normal gcc<CR>", { desc = "Toggle Line Comment" })
end

map("n", "<C-S-k>", '"_dd', { desc = "Delete Line" })
map("i", "<C-S-k>", '<Cmd>normal! "_dd<CR>', { desc = "Delete Line" })
map("x", "<C-S-k>", '<Esc><Cmd>\'<,\'>delete _<CR>', { desc = "Delete Lines" })

map({ "n", "i" }, "<S-A-Down>", "<Cmd>t.<CR>", { desc = "Copy Line Down" })
map({ "n", "i" }, "<S-A-Up>", "<Cmd>t-1<CR>", { desc = "Copy Line Up" })
map("x", "<S-A-Down>", ":<C-u>'<,'>t'><CR>'[V']", { silent = true, desc = "Copy Lines Down" })
map("x", "<S-A-Up>", ":<C-u>'<,'>t'<-1<CR>'[V']", { silent = true, desc = "Copy Lines Up" })

map("n", "<C-]>", ">>", { desc = "Indent Line" })
map("x", "<C-]>", ">gv", { desc = "Indent Lines" })
map("i", "<C-]>", "<C-t>", { desc = "Indent Line" })

map(niv, "<S-A-f>", function()
  require("conform").format { lsp_fallback = true }
end, { desc = "Format Document" })

map("n", "<C-CR>", "o", { desc = "Insert Line Below" })
map("i", "<C-CR>", "<C-o>o", { desc = "Insert Line Below" })
map("n", "<C-S-CR>", "O", { desc = "Insert Line Above" })
map("i", "<C-S-CR>", "<C-o>O", { desc = "Insert Line Above" })

-- Clipboard / undo: insert + visual only
map("x", "<C-c>", '"+y', { desc = "Copy" })
map("x", "<C-x>", '"+d', { desc = "Cut" })
map("x", "<C-v>", '"+P', { desc = "Paste" }) -- visual P: replace without yanking
map("i", "<C-c>", function()
  vim.fn.setreg("+", vim.api.nvim_get_current_line(), "l")
end, { desc = "Copy Line" })
map("i", "<C-x>", '<Cmd>normal! "+dd<CR>', { desc = "Cut Line" })
map("i", "<C-v>", "<C-r><C-o>+", { desc = "Paste" })
map("i", "<C-z>", "<Cmd>undo<CR>", { desc = "Undo" })
map("i", "<C-y>", "<Cmd>redo<CR>", { desc = "Redo" })
map({ "i", "x" }, "<C-a>", "<Esc>ggVG", { desc = "Select All" })
-- <C-w> now closes the tab (below); keep a word-delete key while typing
map("i", "<C-BS>", "<C-w>", { desc = "Delete Word Left" })

-- === Layout & tabs ==========================================================
-- One sidebar slot, Explorer or Source Control, as in VS Code's activity bar
-- (utils/git_sidebar.lua). <C-S-g> needs kitty to pass it through, see
-- the ctrl+shift+g line in ~/.config/kitty/kitty.conf.
map(niv, "<C-b>", call("utils.git_sidebar", "toggle"), { desc = "Toggle Sidebar" })
map(niv, "<C-S-e>", call("utils.git_sidebar", "show", "explorer"), { desc = "Show Explorer" })
map(niv, "<C-S-g>", call("utils.git_sidebar", "show", "scm"), { desc = "Show Source Control" })
map(niv, "<C-\\>", "<Cmd>vsplit<CR>", { desc = "Split Editor" })
map(niv, "<C-S-m>", "<Cmd>Trouble diagnostics toggle<CR>", { desc = "Problems Panel" })
map({ "n", "i", "t" }, "<C-j>", call("utils.term", "toggle"), { desc = "Toggle Panel (terminal)" })

map(niv, "<C-w>", function()
  if vim.bo.buflisted then
    require("nvchad.tabufline").close_buffer()
  else
    pcall(vim.cmd.close) -- tree, Trouble, help, ...
  end
end, { desc = "Close Editor" })

for i = 1, 9 do
  map(niv, ("<C-%d>"):format(i), function()
    local buf = (vim.t.bufs or {})[i]
    if buf then
      require("nvchad.tabufline").goto_buf(buf)
    end
  end, { desc = ("Go to Editor %d"):format(i) })
end

-- Vim's <C-w> window commands, moved to <leader>w. NvChad's <leader>wa/wr/wl
-- (LSP workspace folders) and <leader>wk/wK (which-key) are left alone.
for key, desc in pairs {
  v = "Split vertical",
  s = "Split horizontal",
  o = "Close other windows",
  q = "Close window",
  ["="] = "Equalize sizes",
  x = "Swap with next",
  h = "Go left",
  j = "Go down",
} do
  map("n", "<leader>w" .. key, "<Cmd>wincmd " .. key .. "<CR>", { desc = "Window: " .. desc })
end

local wk_ok, wk = pcall(require, "which-key")
if wk_ok then
  wk.add { { "<leader>w", group = "Windows / Workspace" } }
end
