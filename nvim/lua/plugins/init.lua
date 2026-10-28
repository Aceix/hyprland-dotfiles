return {

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    event = "VeryLazy",
    opts = {
      -- Mirrors what's currently installed via :MasonInstall so the set is
      -- reproducible on a fresh machine instead of living only in
      -- ~/.local/share/nvim/mason on this one.
      ensure_installed = {
        "bash-language-server",
        "dart-debug-adapter",
        "debugpy",
        "delve",
        "docker-compose-language-service",
        "dockerfile-language-server",
        "docker-language-server",
        "eslint_d",
        "go-debug-adapter",
        "golangci-lint",
        "gopls",
        "prettier",
        "stylua",
        "tsgo",
        "typescript-language-server",
        "vtsls",
        "vue-language-server",
        "yaml-language-server",
      },
    },
  },

  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {},
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash Jump" },
      { "S", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
  },

  {
    "3rd/image.nvim",
    build = false,
    lazy = false,
    opts = {
      backend = "kitty", -- Kitty's terminal natively speaks the kitty graphics protocol
      processor = "magick_cli",
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true, -- Automatically pulls down online URL image pathways
          only_render_image_at_cursor = false,
        },
        neorg = { enabled = true },
      },
      max_width = 100,
      max_height = 12,
      max_width_window_percentage = math.huge,
      max_height_window_percentage = math.huge,
      window_overlap_clear_enabled = true, -- Cleans image artifacts when windows hide or move
    },
  },

  {
    "folke/zen-mode.nvim",
    opts = {},
    lazy = false,
  },

  {
    "sudo-tee/opencode.nvim",
    lazy = false,
    config = function()
      require("opencode").setup {
        keymap_prefix = "<leader>ao",
      }
    end,
    dependencies = {
      "MeanderingProgrammer/render-markdown.nvim", -- set up in lua/plugins/render-markdown.lua

      -- Optional, for file mentions and commands completion, pick only one
      "saghen/blink.cmp",
      -- 'hrsh7th/nvim-cmp',

      -- Optional, for file mentions picker, pick only one
      "folke/snacks.nvim",
      -- 'nvim-telescope/telescope.nvim',
      -- 'ibhagwan/fzf-lua',
      -- 'nvim_mini/mini.nvim',
    },
  },

  {
    "j-hui/fidget.nvim",
    opts = {
      -- options
    },
  },

  {
    "stevearc/quicker.nvim",
    ft = "qf",
    ---@module "quicker"
    ---@type quicker.SetupOptions
    opts = {},
  },

  {
    "folke/ts-comments.nvim",
    opts = {},
    event = "VeryLazy",
    enabled = vim.fn.has "nvim-0.10.0" == 1,
  },

  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
    },
  },

  -- {
  --   "ravitemer/codecompanion-history.nvim",
  --   dependencies = { "olimorris/codecompanion.nvim" },
  --   event = "VeryLazy",
  --   config = function()
  --     -- This function safe-guards initialization until lazy finishes cloning the repository
  --     local status, history = pcall(require, "codecompanion-history")
  --     if not status then return end
  --
  --     history.setup({
  --       auto_save = true,
  --       dir_to_save = vim.fn.stdpath("data") .. "/codecompanion-history",
  --       continue_last_chat = true,
  --     })
  --   end,
  -- },

  {
    "karb94/neoscroll.nvim",
    lazy = false,
    config = function()
      local neoscroll = require "neoscroll"

      neoscroll.setup {
        -- Explicitly pass only keys native to Neoscroll's default schema
        mappings = { "<C-u>", "<C-d>", "<C-b>", "<C-f>", "<C-y>", "<C-e>", "zt", "zz", "zb" },
        hide_cursor = true,
        stop_eof = true,
        easing = "quadratic",
        post_hook = function(info)
          if info == "center" then
            vim.cmd "normal! zz"
          end
        end,
      }

      -- Force PageUp / PageDown to invoke smooth window scrolling + 'zz' centering
      -- This works flawlessly across Normal, Insert, and Visual modes natively!
      vim.keymap.set({ "n", "i", "v" }, "<PageUp>", function()
        neoscroll.scroll(-0.5, { move_cursor = true, duration = 250, easing = "quadratic", info = "center" })
      end, { desc = "Smooth scroll half page up" })

      vim.keymap.set({ "n", "i", "v" }, "<PageDown>", function()
        neoscroll.scroll(0.5, { move_cursor = true, duration = 250, easing = "quadratic", info = "center" })
      end, { desc = "Smooth scroll half page down" })
    end,
  },

  -- -- Installs the LazyGit floating pop-up environment
  -- {
  --   "kdheepak/lazygit.nvim",
  --   cmd = { "LazyGit", "LazyGitConfig", "LazyGitCurrentFile" },
  --   dependencies = { "nvim-lua/plenary.nvim" },
  -- },

  {
    "charludo/projectmgr.nvim",
    lazy = false,
  },

  {
    "olimorris/codecompanion.nvim",
    version = "^19.0.0",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
      "ravitemer/mcphub.nvim",
      "ravitemer/codecompanion-history.nvim",
    },
    lazy = false,
    opts = require "configs.codecompanion",
  },

  {
    "stevearc/dressing.nvim",
    lazy = false,
    opts = {},
  },

  {
    "akinsho/flutter-tools.nvim",
    lazy = false,
    ft = "dart",
    cmd = {
      "FlutterRun",
      "FlutterDevices",
      "FlutterEmulators",
      "FlutterReload",
      "FlutterRestart",
      "FlutterQuit",
      "FlutterOutlineToggle",
      "FlutterDevTools",
      "FlutterCopyProfilerUrl",
      "FlutterLspRename",
    },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "stevearc/dressing.nvim",
    },
    opts = require "configs.flutter",
  },

  "nvim-lua/plenary.nvim",

  {
    "nvchad/ui",
    config = function()
      require "nvchad"
    end,
  },

  {
    "nvchad/base46",
    lazy = true,
    build = function()
      require("base46").load_all_highlights()
    end,
  },

  "nvzone/volt", -- optional, needed for theme switcher

  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- test new blink
  { import = "nvchad.blink.lazyspec" },

  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    opts = require "configs.treesitter",
  },

  {
    "mfussenegger/nvim-dap",
    dependencies = {
      -- Provides a nice graphical user interface for debugging
      "rcarriga/nvim-dap-ui",
      -- Required dependency for nvim-dap-ui
      "nvim-neotest/nvim-nio",
      -- Bridges mason.nvim with nvim-dap to easily install debuggers
      "jay-babu/mason-nvim-dap.nvim",
    },
    keys = {
      {
        "<leader>db",
        function()
          require("dap").toggle_breakpoint()
        end,
        desc = "Toggle Breakpoint",
      },
      {
        "<leader>dc",
        function()
          require("dap").continue()
        end,
        desc = "Continue/Start Debugging",
      },
      {
        "<leader>do",
        function()
          require("dap").step_over()
        end,
        desc = "Step Over",
      },
      {
        "<leader>di",
        function()
          require("dap").step_into()
        end,
        desc = "Step Into",
      },
      {
        "<leader>dO",
        function()
          require("dap").step_out()
        end,
        desc = "Step Out",
      },
      {
        "<leader>dr",
        function()
          require("dap").repl.open()
        end,
        desc = "Open REPL",
      },
      {
        "<leader>dt",
        function()
          require("dapui").toggle()
        end,
        desc = "Toggle Debugger UI",
      },
    },
    config = function()
      local dap = require "dap"
      local dapui = require "dapui"

      -- Initialize mason-nvim-dap to automatically install/manage debug adapters
      require("mason-nvim-dap").setup {
        -- Add the debuggers you want to ensure are installed
        ensure_installed = { "python", "delve" }, -- Example: python and go debuggers
        automatic_installation = true,
      }

      -- Initialize the UI
      dapui.setup()

      -- Automatically open/close the UI when debugging starts/ends
      dap.listeners.before.attach.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.launch.dapui_config = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated.dapui_config = function()
        dapui.close()
      end
      dap.listeners.before.event_exited.dapui_config = function()
        dapui.close()
      end
    end,
  },

  {
    "folke/trouble.nvim",
    lazy = true,
    cmd = "Trouble",
    opts = {},
  },

  {
    "MagicDuck/grug-far.nvim",
    lazy = true,
    cmd = "GrugFar",
    opts = { headerMaxWidth = 80 },
  },
}
