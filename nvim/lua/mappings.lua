require "nvchad.mappings"

-- NvChad's duplicates of <leader>fr / <leader>gc / <leader>gs (below)
for _, lhs in ipairs { "<leader>fo", "<leader>cm", "<leader>gt" } do
  vim.keymap.del("n", lhs)
end

local map = vim.keymap.set
local call = require "utils.call"

-- Tab / Shift+Tab as in VS Code: they indent / outdent a selection (and the
-- current line while typing, see plugins/blink.lua) and never switch tabs;
-- that's <C-Tab> / <C-S-Tab> below. In Normal mode they're a no-op, overriding
-- NvChad's next/prev buffer. <Nop> rather than unmapping: most terminals send
-- Tab as <C-i>, which would otherwise jump forward in the jumplist.
map("n", "<Tab>", "<Nop>", { desc = "Nothing (VS Code)" })
map("n", "<S-Tab>", "<Nop>", { desc = "Nothing (VS Code)" })
map("v", "<Tab>", ">gv", { desc = "Indent selection right" })
map("v", "<S-Tab>", "<gv", { desc = "Indent selection left" })

map("n", "<leader>uz", call("utils.diff_zen", "toggle"), { desc = "Toggle Zen Mode" })

-- === VS Code-style selection & word motion ================================
-- Plain <S-arrow> keys are intentionally NOT mapped here: Neovim's built-in
-- `keymodel=startsel` (set in lua/options.lua) already makes them start a
-- charwise Visual selection and keep extending it while Shift is held, from
-- normal, visual and insert mode. Remapping them would break that.

-- Ctrl+<arrow> = word motion (b / w), matching insert mode, in normal & visual.
map({ "n", "x" }, "<C-Left>", "b", { desc = "Word left" })
map({ "n", "x" }, "<C-Right>", "w", { desc = "Word right" })

-- Ctrl+Shift+<arrow> = extend the selection one word at a time (VS Code).
-- If a selection is already active, just move its active end; otherwise open a
-- charwise Visual selection first. (Needs a terminal that reports C-S-arrow,
-- e.g. the kitty keyboard protocol.)
local function word_extend(motion)
  return function()
    if vim.fn.mode():find "^[vV\22sS\19]" then
      return motion
    end
    return "v" .. motion
  end
end
map({ "n", "x" }, "<C-S-Left>", word_extend "b", { expr = true, desc = "Select word left" })
map({ "n", "x" }, "<C-S-Right>", word_extend "e", { expr = true, desc = "Select word right" })
map("i", "<C-S-Left>", "<Esc>vb", { desc = "Select word left" })
map("i", "<C-S-Right>", "<Esc>lve", { desc = "Select word right" })

-- Only in file buffers: quickfix (editable under quicker.nvim), help, ... keep
-- <CR> (jump to the line)
for key, open in pairs { ["<CR>"] = "o", ["<S-CR>"] = "O" } do
  map("n", key, function()
    return vim.bo.buftype == "" and vim.bo.modifiable and open or key
  end, { expr = true })
end

map("n", ";", ":", { desc = "CMD enter command mode" })
map("i", "jk", "<ESC>")

-- Bottom terminal pane with tabbed shells, see lua/utils/term.lua
local function term(fn, ...)
  return call("utils.term", fn, ...)
end
map({ "n", "t" }, "<C-`>", term "toggle", { desc = "Terminal Toggle Pane" })
map({ "n", "t" }, "<C-S-`>", term "new", { desc = "Terminal New Tab" })
map({ "n", "t" }, "<C-A-`>", term "toggle_height", { desc = "Maximize Bottom Panel" })
-- <C-Tab> / <C-S-Tab> in a terminal cycle the pane's tabs; see the unified
-- buf_cycle() maps further down (they also handle code buffers).

map("n", "<leader>ut", call("nvchad.themes", "open"), { desc = "Change Theme" })

-- Switch between projects (project.nvim + telescope)
map("n", "<C-o>", call("utils.project_picker", "switch_project"), { desc = "Switch Project" })

-- AI (CodeCompanion)
map({ "n", "v" }, "<leader>aa", function()
  vim.cmd "CodeCompanionChat Toggle"
  vim.cmd "startinsert"
end, { desc = "AI Chat Toggle & Enter Insert Mode" })
map({ "n", "v" }, "<leader>ac", "<cmd>CodeCompanionActions<cr>", { desc = "AI Actions Menu" })
map({ "n", "v" }, "<leader>ai", "<cmd>CodeCompanion<cr>", { desc = "AI Inline Prompt" })
map("n", "<leader>ah", "<cmd>CodeCompanionHistory<cr>", { desc = "AI Browse Saved Chat History" })
map("n", "<leader>aS", "<cmd>CodeCompanionSummaries<cr>", { desc = "AI Browse Chat Summaries" })

-- <C-Tab> / <C-S-Tab>: cycle forward / backward, mode-aware by buffer type.
--   * terminal / Problems -> cycle the bottom panel's tabs (utils.term)
--   * anything else    -> VS Code's tab switcher popup, most recently used first
--                         (utils.buf_mru; required now so it records from startup)
-- The buftype check is what stops a code buffer being loaded into the terminal
-- pane when it's focused in Normal mode.
local buf_mru = require "utils.buf_mru"
local function buf_cycle(dir)
  if vim.bo.buftype == "terminal" or require("utils.term").is_panel_win(vim.api.nvim_get_current_win()) then
    require("utils.term").cycle(dir)
  else
    buf_mru.cycle(dir)
  end
end
map({ "n", "t", "i", "v" }, "<C-Tab>", function() buf_cycle(1) end, { desc = "Next buffer / terminal tab" })
map({ "n", "t", "i", "v" }, "<C-S-Tab>", function() buf_cycle(-1) end, { desc = "Prev buffer / terminal tab" })

-- tabufline switches the *current* window's buffer, so clicking a tab (or
-- <C-1..9>, next/prev) from the terminal pane or a panel (nvim-tree, outline,
-- Trouble, ...) opened the file in there. Hop to a code window first.
do
  local tl = require "nvchad.tabufline"
  for _, name in ipairs { "goto_buf", "next", "prev" } do
    local switch = tl[name]
    tl[name] = function(...)
      require("utils.term").focus_code_win()
      return switch(...)
    end
  end

  -- close_buffer picks its branch from the *current* buffer, so closing a
  -- tab (its ✕, <leader>x) while the Explorer had focus wiped the file and
  -- closed its window instead, the Explorer taking the whole screen. Close
  -- it from the window showing it.
  local close = tl.close_buffer
  tl.close_buffer = function(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 and win ~= vim.api.nvim_get_current_win() then
      return vim.api.nvim_win_call(win, function()
        return close(bufnr)
      end)
    end
    return close(bufnr)
  end
end

-- Right-click on nvim-tree opens VS Code's Explorer context menu
-- (utils/tree_menu.lua); anywhere else keeps the normal right-click. Global
-- rather than buffer-local because it's the clicked window that counts, not
-- the current one. utils/test_gutter.lua replaces this once neotest loads and
-- falls back to it off the gutter.
map("n", "<RightMouse>", call("utils.tree_menu", "right_click"), { expr = true, desc = "Context menu" })

-- The Explorer skips auto-revealing dependency/outside files (configs/nvim-tree.lua);
-- this reveals the current file regardless
map("n", "<leader>E", function()
  require("nvim-tree.api").tree.find_file { open = true, focus = true }
end, { desc = "Reveal file in Explorer" })

-- Open file finder by pressing leader twice
map("n", "<leader><leader>", "<cmd>Telescope find_files<cr>", { desc = "Telescope Find Files" })

-- Window navigation (Ctrl+Alt+arrows)
map("n", "<CA-Left>", "<C-w>h", { desc = "Window move left" })
map("n", "<CA-Down>", "<C-w>j", { desc = "Window move down" })
map("n", "<CA-Up>", "<C-w>k", { desc = "Window move up" })
map("n", "<CA-Right>", "<C-w>l", { desc = "Window move right" })

-- Jump backward/forward in code navigation history (Jump list)
map("n", "<A-Left>", "<C-o>", { desc = "Jump backward in code history" })
map("n", "<A-Right>", "<C-i>", { desc = "Jump forward in code history" })

-- Swap lines with Alt+Up/Down
map("n", "<A-Up>", "<cmd>m .-2<CR>==", { desc = "Swap line up" })
map("n", "<A-Down>", "<cmd>m .+1<CR>==", { desc = "Swap line down" })
map("i", "<A-Up>", "<Esc><cmd>m .-2<CR>==gi", { desc = "Swap line up" })
map("i", "<A-Down>", "<Esc><cmd>m .+1<CR>==gi", { desc = "Swap line down" })

-- Git shortcuts
map("n", "<leader>gs", "<cmd> Telescope git_status <CR>", { desc = "Git status" })

map("n", "<leader>gh", "<cmd> Gitsigns stage_hunk <CR>", { desc = "Stage current hunk" })
map("n", "<leader>gu", "<cmd> Gitsigns undo_stage_hunk <CR>", { desc = "Undo stage hunk" })
map("n", "<leader>gr", "<cmd> Gitsigns reset_hunk <CR>", { desc = "Reset current hunk" })
map("n", "<leader>gp", "<cmd> Gitsigns preview_hunk <CR>", { desc = "Preview hunk float" })

map("n", "<leader>gb", "<cmd> Gitsigns toggle_current_line_blame <CR>", { desc = "Toggle inline line blame" })
map("n", "<leader>gc", "<cmd> Telescope git_commits <CR>", { desc = "Fuzzy view commits" })
map("n", "<leader>gd", "<cmd> DiffviewOpen <CR>", { desc = "Open split branch diff" })
map("n", "<leader>gx", "<cmd> DiffviewClose <CR>", { desc = "Exit split branch diff" })

-- Source Control sidebar (utils/git_sidebar.lua) and GitLens-style extras
local function host(fn, opts)
  return call("utils.git_host", fn, opts)
end

map("n", "<leader>gg", call("utils.git_sidebar", "show", "scm"), { desc = "Source Control sidebar" })
map("n", "<leader>gC", "<cmd>Neogit commit<CR>", { desc = "Commit…" })
map("n", "<leader>gf", "<cmd>DiffviewFileHistory %<CR>", { desc = "File history" })
map("x", "<leader>gf", ":DiffviewFileHistory<CR>", { desc = "Line history (selection)" })
map("n", "<leader>gB", call("gitsigns", "blame_line", { full = true }), { desc = "Blame hover (commit details)" })
map("n", "<leader>gl", "<cmd>Gitsigns blame<CR>", { desc = "Blame panel (whole file)" })
map("n", "<leader>gi", "<cmd>Gitsigns preview_hunk_inline<CR>", { desc = "Peek change inline" })
map("n", "<leader>gw", "<cmd>Gitsigns toggle_word_diff<CR>", { desc = "Toggle word diff" })
map("n", "<leader>gS", host "sync", { desc = "Sync (pull --rebase, push)" })
map("n", "<leader>gF", call("utils.git_autofetch", "fetch"), { desc = "Fetch now" })
map({ "n", "x" }, "<leader>go", host("browse", { what = "file" }), { desc = "Open on remote (file / lines)" })
map({ "n", "x" }, "<leader>gy", host("browse", { what = "permalink", copy = true }), { desc = "Copy permalink" })
map("n", "<leader>gP", host "pull_requests", { desc = "Pull / merge requests" })
map("n", "<leader>gN", host "create_pr", { desc = "Create pull / merge request" })
map("n", "<leader>gR", host "review", { desc = "Review current PR / MR" })
map("n", "<leader>gI", host "issues", { desc = "Issues" })

-- Visual Mode Git Mappings
map("v", "<leader>gh", function()
  require("gitsigns").stage_hunk { vim.fn.line ".", vim.fn.line "v" }
end, { desc = "Stage highlighted lines" })
map("v", "<leader>gr", function()
  require("gitsigns").reset_hunk { vim.fn.line ".", vim.fn.line "v" }
end, { desc = "Reset highlighted lines" })

map("n", "<leader>tw", "<cmd>set wrap!<CR>", { desc = "Toggle word wrap" })

-- Terminal pane (keyboard fallbacks for <C-`> / <C-S-`>, which need a terminal
-- emulator that speaks the kitty keyboard protocol to distinguish the two)
map("n", "<leader>tt", term "toggle", { desc = "Terminal Toggle Pane" })
map("n", "<leader>tn", term "new", { desc = "Terminal New Tab" })
map("n", "<leader>t]", term("cycle", 1), { desc = "Terminal Next Tab" })
map("n", "<leader>t[", term("cycle", -1), { desc = "Terminal Prev Tab" })
map("n", "<leader>tx", term "close", { desc = "Terminal Close Tab" })
map("n", "<leader>tz", term "toggle_height", { desc = "Maximize Bottom Panel" })

-- Code / LSP Actions (<leader>c)
-- Refactoring & Actions
map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "Code Action" })
map("n", "<leader>cr", vim.lsp.buf.rename, { desc = "Rename Symbol" })
map({ "n", "v" }, "<leader>cf", function()
  require("conform").format { lsp_fallback = true }
end, { desc = "Format Code" })

-- Symbols (<leader>co, the outline, is in plugins/outline.lua)
map("n", "<leader>cs", "<cmd>Telescope lsp_document_symbols<cr>", { desc = "Document Symbols" })
map("n", "<leader>cS", "<cmd>Telescope lsp_workspace_symbols<cr>", { desc = "Workspace Symbols" })

-- Navigation, Definitions & References
map("n", "<leader>cp", "<cmd>Telescope lsp_definitions<cr>", { desc = "Go to Definition" })
map("n", "<leader>cD", vim.lsp.buf.declaration, { desc = "Go to Declaration" })
map("n", "<leader>ci", "<cmd>Telescope lsp_implementations<cr>", { desc = "Go to Implementation" })
map("n", "<leader>ct", "<cmd>Telescope lsp_type_definitions<cr>", { desc = "Type Definition" })
map("n", "<leader>cR", "<cmd>Telescope lsp_references<cr>", { desc = "View References" })

-- Call Hierarchy
map("n", "<leader>cc", "<cmd>Telescope lsp_incoming_calls<cr>", { desc = "Call Hierarchy (Incoming)" })
map("n", "<leader>cC", "<cmd>Telescope lsp_outgoing_calls<cr>", { desc = "Caller Hierarchy (Outgoing)" })

-- Hover & Diagnostics
-- The line's diagnostics in a float that <Esc> or q closes, from the code or
-- from inside the float. Those keys are only taken over while it's open: after
-- that <Esc> clears the search again and q records macros (and any map the
-- buffer had for them comes back).
local diag_floats = {} -- code buffer -> its float window
local function diagnostic_float()
  local buf = vim.api.nvim_get_current_buf()
  local float_buf, win = vim.diagnostic.open_float()
  if not win or diag_floats[buf] == win then
    return -- nothing on this line, or a second gl just went into the float
  end
  diag_floats[buf] = win

  local keys, saved = { "<Esc>", "q" }, {}
  for _, key in ipairs(keys) do
    local m = vim.fn.maparg(key, "n", false, true)
    saved[key] = m.buffer == 1 and m or nil
  end
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
  for _, b in ipairs { buf, float_buf } do
    for _, key in ipairs(keys) do
      map("n", key, close, { buffer = b, nowait = true, desc = "Close diagnostic float" })
    end
  end

  -- However it closes (these keys, moving the cursor, ...), give the keys back
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      diag_floats[buf] = nil
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        for _, key in ipairs(keys) do
          pcall(vim.keymap.del, "n", key, { buffer = buf })
          if saved[key] then
            vim.fn.mapset("n", false, saved[key])
          end
        end
      end)
    end,
  })
end

map("n", "<leader>ch", vim.lsp.buf.hover, { desc = "Hover Documentation" })
map("n", "<leader>ck", vim.lsp.buf.signature_help, { desc = "Signature Help" })
map("n", "<leader>ce", diagnostic_float, { desc = "Line Diagnostics Float" })
map("n", "<leader>cq", vim.diagnostic.setqflist, { desc = "Diagnostics Quickfix List" })
map("n", "<leader>uh", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled { bufnr = 0 }, { bufnr = 0 })
end, { desc = "Toggle Inlay Hints" })

-- Register WhichKey group labels
local wk_ok, wk = pcall(require, "which-key")
if wk_ok then
  wk.add {
    { "<leader>c", group = "Code / LSP" },
    { "<leader>cd", group = "Diagnostics / Trouble" },
    { "<leader>cT", group = "Test (Neotest)" },
    { "<leader>cj", group = "Java (jdtls)" },
    { "<leader>f", group = "Find / Telescope" },
    { "<leader>s", group = "Search & Replace" },
    { "<leader>d", group = "Debugger" },
    { "<leader>u", group = "UI Toggles" },
    { "<leader>t", group = "Terminal / Toggles" },
    { "<leader>T", group = "Tools" },
    { "<leader>g", group = "Git" },
    { "<leader>a", group = "AI Assistant" },
    { "<leader>r", group = "Remote (SSH / Devcontainer)" },
  }
end

-- File & Navigation Pickers (<leader>f)
map("n", "<leader>ff", "<cmd>Telescope find_files<cr>", { desc = "Find Files" })
map("n", "<leader>fg", "<cmd>Telescope live_grep<cr>", { desc = "Live Grep (Text Search)" })
map("n", "<leader>fb", "<cmd>Telescope buffers<cr>", { desc = "Open Buffers" })
map("n", "<leader>fr", "<cmd>Telescope oldfiles<cr>", { desc = "Recent Files" })
map("n", "<leader>fh", "<cmd>Telescope help_tags<cr>", { desc = "Help Tags" })

-- Search & Replace (<leader>s)
map("n", "<leader>sr", "<cmd>GrugFar<cr>", { desc = "Search & Replace Project" })
map("n", "<leader>sw", function()
  require("grug-far").open { prefills = { search = vim.fn.expand "<cword>" } }
end, { desc = "Search Current Word" })

-- Diagnostics & Trouble (<leader>cd & [d / ]d)
map("n", "<leader>cdd", "<cmd>Trouble diagnostics toggle<cr>", { desc = "Diagnostics Panel (Trouble)" })
map("n", "<leader>cdb", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", { desc = "Buffer Diagnostics (Trouble)" })
map("n", "<leader>cdl", "<cmd>Trouble loclist toggle<cr>", { desc = "Location List (Trouble)" })
map("n", "<leader>cdq", "<cmd>Trouble qflist toggle<cr>", { desc = "Quickfix List (Trouble)" })
map("n", "gl", diagnostic_float, { desc = "Open floating diagnostic message" })
map("n", "[d", vim.diagnostic.goto_prev, { desc = "Previous Diagnostic" })
map("n", "]d", vim.diagnostic.goto_next, { desc = "Next Diagnostic" })

-- UI Layout & Toggles (<leader>u)
map("n", "<leader>uW", "<cmd>Twilight<cr>", { desc = "Toggle Twilight Dimming" })
map("n", "<leader>uT", call("configs.transparency", "toggle"), { desc = "Toggle Transparency/Opaque" })
map("n", "<leader>uf", call("utils.autoresize", "toggle"), { desc = "Toggle Window Auto-Resize" })
map("n", "<leader>um", call("utils.maximize", "toggle"), { desc = "Maximize Split Window" })
map("n", "<leader>ui", call("utils.svg_preview", "toggle"), { desc = "Toggle SVG Code/Preview" })
-- Also flips the auto-open flag read by the MiniMapAutoOpen autocmd (see
-- lua/autocmds.lua), so closing the map keeps it closed until toggled back on.
map("n", "<leader>uM", function()
  local minimap = require "mini.map"
  minimap.toggle()
  vim.g.minimap_auto_open = minimap.current.win_data[vim.api.nvim_get_current_tabpage()] ~= nil
end, { desc = "Toggle Minimap" })

-- VS Code-style shortcuts on top of everything above (toggle in lua/settings.lua)
if require("settings").vscode_keys then
  require "vscode_keys"
end
