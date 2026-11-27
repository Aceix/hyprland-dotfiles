-- PHP / Laravel. PHPantom formats (Pint or php-cs-fixer when the project
-- requires one, its own formatter otherwise) and runs PHPStan / Mago itself
-- when the project is set up for them, so there are no conform or nvim-lint
-- entries: <leader>cf falls back to the server.
return {
  mason = { "phpantom_lsp", { "php-debug-adapter", needs = "node" } },
  lsp = { phpantom_lsp = {} },
  parsers = { "php", "php_only", "phpdoc", "blade" },

  -- Xdebug 3 (xdebug.mode=debug, xdebug.start_with_request=yes). For Docker /
  -- Sail add pathMappings in .vscode/launch.json, which nvim-dap reads.
  dap = function(dap)
    dap.adapters.php = { type = "executable", command = "php-debug-adapter" }
    dap.configurations.php = {
      { type = "php", request = "launch", name = "PHP: Listen for Xdebug", port = 9003 },
    }
  end,

  neotest = {
    detect = function(cwd)
      return vim.uv.fs_stat(cwd .. "/composer.json") ~= nil
    end,
    adapters = function()
      return {
        require "neotest-pest",
        -- Pest projects' files are Pest's, even the PHPUnit-style ones
        require "neotest-phpunit" { root_ignore_files = { "tests/Pest.php" } },
      }
    end,
  },

  deps = function(d)
    local php = d.exe("php", "install PHP")
    return {
      test = {
        php = {
          label = "PHP tests",
          php,
          d.file(
            "vendor/bin/{pest,phpunit}",
            "PHPUnit or Pest",
            "composer require --dev pestphp/pest (or phpunit/phpunit)"
          ),
        },
      },
      debug = {
        php = {
          label = "PHP debugging",
          php,
          d.exe("node", "install Node.js"),
          d.mason("php-debug-adapter", "php-debug-adapter"),
        },
      },
    }
  end,
}
