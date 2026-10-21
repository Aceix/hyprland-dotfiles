-- Adapters are required inside this function (rather than at spec level like
-- most configs/ files here) so they only resolve once lazy has put them on the
-- runtimepath. Each adapter picks up the projects it recognises, so unrelated
-- ones stay dormant in a repo they don't match.
return function()
  -- base46 theme colors for the gutter icons and summary (chadrc integrations)
  pcall(dofile, vim.g.base46_cache .. "neotest")

  -- Every run (debug runs too) gets the env of the nearest .env.test between
  -- the tests and the project root, read afresh each time
  local function with_env_test(adapter)
    local build_spec = adapter.build_spec
    adapter.build_spec = function(args)
      local pos, root = args.tree:data(), args.tree:root():data().path
      local file = vim.fs.find(".env.test", {
        upward = true,
        path = pos.type == "dir" and pos.path or vim.fs.dirname(pos.path),
        stop = vim.fs.dirname(root),
      })[1]
      if not file then
        return build_spec(args)
      end
      local env = {}
      for line in io.lines(file) do
        local key, value = line:match "^%s*([%w_]+)%s*=%s*(.-)%s*$"
        if not key then
          key, value = line:match "^%s*export%s+([%w_]+)%s*=%s*(.-)%s*$"
        end
        if key then
          env[key] = value:match '^"(.*)"$' or value:match "^'(.*)'$" or value
        end
      end
      vim.schedule(function()
        vim.notify("Loading test env from: " .. vim.fn.fnamemodify(file, ":~:."), vim.log.levels.INFO, { title = "neotest" })
      end)

      -- neotest-java starts its debug JVM inside build_spec, from nvim's own
      -- env, so for debug runs that holds the vars until build_spec is done
      local saved = {}
      if args.strategy == "dap" then
        for key, value in pairs(env) do
          saved[key] = vim.env[key] or vim.NIL
          vim.env[key] = value
        end
      end
      local ok, specs = pcall(build_spec, args)
      for key, value in pairs(saved) do
        vim.env[key] = value ~= vim.NIL and value or nil
      end
      if not ok then
        error(specs, 0)
      end

      for _, spec in ipairs(specs and (vim.islist(specs) and specs or { specs }) or {}) do
        spec.env = vim.tbl_extend("force", spec.env or {}, env)
      end
      return specs
    end
    return adapter
  end

  require("neotest").setup {
    adapters = vim.tbl_map(with_env_test, {
      -- Go: reads `go test -json`, works with delve for `<leader>Td`
      require "neotest-golang",

      -- Dart/Flutter: `use_lsp` leans on the dartls outline so generated or
      -- interpolated test names still resolve. Swap `command` to "dart" for
      -- pure Dart packages, or "fvm flutter" when using fvm.
      require "neotest-dart" {
        command = "flutter",
        use_lsp = true,
      },

      -- JS/TS: jest and vitest each claim only the projects whose config they
      -- find, so both can sit here at once.
      require "neotest-jest" {
        jestCommand = "npm test --",
        env = { CI = true },
      },
      require "neotest-vitest",

      -- Java: needs jdtls attached; run `:NeotestJava setup` once to fetch the
      -- JUnit Platform Console Standalone jar. Its compile step is swapped for
      -- one that waits for (and reports on) the jdtls build, utils/java_build.lua.
      require "neotest-java"({}, { lsp_compiler = require("utils.java_build").compiler() }),

      -- Python: pytest (or unittest when pytest isn't installed) from the
      -- project's own venv, found the same way as the LSP and debugger.
      require "neotest-python" {
        python = function(root)
          return require("utils.python").path(root)
        end,
        dap = { justMyCode = false },
        -- pytest hides print() output from passing tests; -s lets it stream
        -- live into Test Results (unittest never captures, and reads -s as
        -- its start directory, so only for pytest)
        args = function(runner)
          return runner == "pytest" and { "-s" } or {}
        end,
      },
    }),

    -- Clickable gutter buttons, see utils/test_gutter.lua
    consumers = {
      test_gutter = require("utils.test_gutter").consumer,
    },

    -- VS Code's play icons on tests that haven't run yet; neotest swaps them
    -- for pass/fail/running once there's a result.
    icons = {
      test = vim.fn.nr2char(0xeb2c), -- codicon play
      namespace = vim.fn.nr2char(0xeb9e), -- codicon run-all
    },

    -- Pass/fail lives in the (clickable) gutter like VS Code; an end-of-line
    -- copy would also paint a play icon after every untested function.
    status = { signs = true, virtual_text = false },
    output = { open_on_run = false },
    -- Trouble/quickfix already handle diagnostics lists, keep test failures in
    -- the neotest panels instead.
    quickfix = { enabled = false },
    summary = {
      open = "botright vsplit | vertical resize 50",
    },
  }

  -- Warn and stop when a run's toolchain is missing (utils/deps.lua)
  require("utils.deps").guard_neotest()

  -- Live run logs in a "Test Results" tab of the bottom pane (utils/test_results.lua)
  require("utils.test_results").setup()
end
