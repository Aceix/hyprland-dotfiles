-- This file needs to have same structure as nvconfig.lua
-- https://github.com/NvChad/ui/blob/v3.0/lua/nvconfig.lua
-- Please read that file to know all available options :(

---@type ChadrcConfig
local M = {}

M.base46 = {
	theme = "dark_horizon",
  transparency = true,

  -- neotest isn't in base46's default set; loading it themes the test
  -- explorer and gutter icons
  integrations = { "neotest" },

  hl_override = {
		-- Comment = { italic = true },
		["@comment"] = { italic = true },

    -- NvimTree git file-status colors, kept off red/yellow so those stay
    -- reserved for LSP diagnostics (errors/warnings). Staged, Merge and
    -- Renamed aren't themeable through this table (base46's nvimtree
    -- integration doesn't predefine those keys) -- they're set directly
    -- in the nvim-tree config instead, see lua/configs/nvim-tree.lua.
    NvimTreeGitNew     = { fg = "#9ECE6A" }, -- green: untracked/new
    NvimTreeGitDirty   = { fg = "#4EC9B0" }, -- teal: unstaged modification
    NvimTreeGitDeleted = { fg = "#FF79C6" }, -- pink/magenta: deleted
    NvimTreeGitIgnored = { fg = "#5C6370" }, -- grey: ignored

    -- The whole side bar's right edge (configs/edgy.lua), in the accent of the
    -- terminal pane's top rule (utils/term.lua: tabufline's TbBufOn fg).
    -- nvim-tree's own group, as nvim-tree re-sets its window's 'winhighlight'.
    NvimTreeWinSeparator = { fg = "white", bg = "NONE", bold = true },

    -- Gutter run buttons (utils/test_gutter.lua) green like VS Code's
    NeotestTest = { fg = "green" },
    NeotestNamespace = { fg = "green" },

    -- Diffs like VS Code's: tinted lines that keep their syntax colors, the
    -- changed words tinted stronger; this is the new side (green), the old
    -- one is DiffOld* below (utils/diff.lua). Filler lines just dim hatching.
    DiffAdd = { fg = "NONE", bg = { "green", "black", 78 } },
    DiffChange = { fg = "NONE", bg = { "green", "black", 88 } },
    DiffText = { fg = "NONE", bg = { "green", "black", 60 } },
    DiffDelete = { fg = "one_bg3", bg = "NONE", bold = false },
	},

  -- Statusline groups the base46 statusline integration doesn't predefine,
  -- used by the custom modules in lua/configs/statusline.lua. Colors are
  -- base_30 names rather than hex so they follow the active theme.
  hl_add = {
    St_Recording = { fg = "red", bg = "statusline_bg", bold = true },
    St_Search = { fg = "cyan", bg = "statusline_bg" },
    St_Dap = { fg = "orange", bg = "statusline_bg", bold = true },
    -- nvim-dap gutter signs, see configs/dap.lua
    DapBreakpoint = { fg = "red" },
    DapBreakpointRejected = { fg = "grey" },
    DapLogPoint = { fg = "blue" },
    DapStopped = { fg = "green" },
    DapStoppedLine = { bg = "one_bg2" },
    St_TestPass = { fg = "green", bg = "statusline_bg" },
    St_TestFail = { fg = "red", bg = "statusline_bg" },
    St_TestRun = { fg = "yellow", bg = "statusline_bg" },
    St_Flutter = { fg = "blue", bg = "statusline_bg" },
    St_Anomaly = { fg = "orange", bg = "statusline_bg" },
    St_FileModified = { fg = "yellow", bg = "lightbg" },
    St_Remote = { fg = "black", bg = "green", bold = true },
    -- Source Control sidebar tabs and GitLens panel (utils/git_sidebar.lua,
    -- utils/git_panel.lua)
    GitSidebarTab = { fg = "light_grey", bg = "darker_black" },
    GitSidebarTabActive = { fg = "white", bg = "one_bg2", bold = true },
    GitPanelSection = { fg = "blue", bold = true },
    GitPanelBranch = { fg = "white" },
    GitPanelCurrent = { fg = "green", bold = true },
    GitPanelRemote = { fg = "cyan" },
    GitPanelTag = { fg = "yellow" },
    GitPanelStash = { fg = "purple" },
    GitPanelDim = { fg = "light_grey", italic = true },
    -- The old side of a diff, red (see DiffAdd above)
    DiffOldAdd = { bg = { "red", "black", 78 } },
    DiffOldChange = { bg = { "red", "black", 88 } },
    DiffOldText = { bg = { "red", "black", 60 } },
  },
}

M.nvdash = {
  load_on_startup = true,
  buttons = {
    { txt = "  Projects", keys = "fp", cmd = ":lua require('utils.project_picker').switch_project()" },
    { txt = "  Find File", keys = "ff", cmd = "Telescope find_files" },
    { txt = "  Recent Files", keys = "fo", cmd = "Telescope oldfiles" },
    { txt = "󰈭  Find Word", keys = "fw", cmd = "Telescope live_grep" },
    { txt = "󱥚  Themes", keys = "th", cmd = ":lua require('nvchad.themes').open()" },
    { txt = "  Mappings", keys = "ch", cmd = "NvCheatsheet" },

    { txt = "─", hl = "NvDashFooter", no_gap = true, rep = true },

    {
      txt = function()
        local stats = require("lazy").stats()
        local ms = math.floor(stats.startuptime) .. " ms"
        return "  Loaded " .. stats.loaded .. "/" .. stats.count .. " plugins in " .. ms
      end,
      hl = "NvDashFooter",
      no_gap = true,
      content = "fit",
    },

    { txt = "─", hl = "NvDashFooter", no_gap = true, rep = true },
  },
}

M.ui = {
  tabufline = {
    lazyload = false,

    -- The stock treeOffset only pads for an NvimTree window, so the tabs
    -- jumped left whenever the side bar showed Source Control instead.
    -- Pad for whichever view the side bar holds (utils/git_sidebar.lua),
    -- styled the same either way, its right edge continued (configs/edgy.lua).
    modules = {
      treeOffset = function()
        local sidebar = require "utils.git_sidebar"
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if
            vim.api.nvim_win_get_config(win).relative == ""
            and vim.api.nvim_win_get_position(win)[2] == 0
            and sidebar.is_sidebar_win(win)
          then
            local w = vim.api.nvim_win_get_width(win)
            return "%#NvimTreeNormal#" .. (" "):rep(w) .. "%#NvimTreeWinSeparator#┃"
          end
        end
        return ""
      end,
    },
  },

  statusline = {
    separator_style = "round",

    -- `lsp_msg` has to stay in the order: lua/autocmds.lua overwrites
    -- nvchad.stl.utils.state.lsp_msg to render the CodeCompanion "AI
    -- thinking" spinner, so dropping the module would silently kill it.
    order = {
      "remote", "mode", "file", "git",
      "%=", "recording", "search", "dap", "neotest", "lsp_msg", "%=",
      "diagnostics", "lsp", "anomaly", "flutter", "cwd", "cursor",
    },
    modules = require "configs.statusline",
  },
}

return M

