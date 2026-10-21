-- jdtls is started per project by nvim-jdtls rather than by `vim.lsp.enable`,
-- so the pieces NvChad normally injects through `vim.lsp.config("*")`
-- (capabilities, on_init) have to be passed explicitly below.
return function()
  local jdtls = require "jdtls"
  local mason = vim.fn.stdpath "data" .. "/mason"
  local nvchad_lsp = require "nvchad.configs.lspconfig"

  -- Extension jars that teach jdtls to debug and to run JUnit. neotest-java
  -- and the `dap` strategy behind <leader>cTd both go through these.
  local bundles = vim.fn.glob(
    mason .. "/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar",
    true,
    true
  )
  vim.list_extend(bundles, vim.fn.glob(mason .. "/packages/java-test/extension/server/*.jar", true, true))

  -- Offer every JDK sdkman has installed, so a project pinned to an older
  -- release still compiles against the right one.
  local runtimes = {}
  for name, kind in vim.fs.dir(vim.env.HOME .. "/.sdkman/candidates/java") do
    local major = name:match "^(%d+)"
    if major and kind == "directory" then
      table.insert(runtimes, {
        name = "JavaSE-" .. major,
        path = vim.env.HOME .. "/.sdkman/candidates/java/" .. name,
      })
    end
  end

  -- One jdtls per repo, not per module: in a multi-module build the repo root
  -- (.git next to a build file) imports every module. neotest-java finds its
  -- root the same way and sends all its requests to a single jdtls client, so
  -- a module-rooted jdtls answers "Given URI does not belong to any Java
  -- project" for the other modules.
  local build_files = {
    "pom.xml",
    "settings.gradle",
    "settings.gradle.kts",
    "build.gradle",
    "build.gradle.kts",
    "mvnw",
    "gradlew",
  }
  local function find_root(buf)
    local git = vim.fs.root(buf, ".git")
    if git and vim.iter(build_files):any(function(f)
      return vim.uv.fs_stat(vim.fs.joinpath(git, f)) ~= nil
    end) then
      return git
    end
    return vim.fs.root(buf, build_files) or git
  end

  -- Lombok: mason's jdtls ships lombok.jar but its launcher doesn't load it,
  -- so jdtls couldn't see @Getter/@Builder/... members and wrote "Unresolved
  -- compilation problem" stubs into target/classes, breaking tests (and
  -- Spring contexts) until the next `mvn` build overwrote them. The agent only
  -- acts on Lombok annotations, so it's a no-op in projects without Lombok.
  local cmd = { mason .. "/bin/jdtls" }
  local lombok = mason .. "/packages/jdtls/lombok.jar"
  if vim.uv.fs_stat(lombok) then
    table.insert(cmd, "--jvm-arg=-javaagent:" .. lombok)
  end

  local function attach()
    local root = find_root(0)

    if not root then
      return
    end

    jdtls.start_or_attach {
      -- One workspace per project; sharing a data dir across projects makes
      -- jdtls rebuild its index on every switch.
      cmd = vim.list_extend(vim.deepcopy(cmd), {
        "-data",
        vim.fn.stdpath "cache" .. "/jdtls/" .. vim.fn.fnamemodify(root, ":t"),
      }),
      root_dir = root,
      capabilities = require("blink.cmp").get_lsp_capabilities(nvchad_lsp.capabilities),
      on_init = nvchad_lsp.on_init,
      init_options = {
        bundles = bundles,
        extendedClientCapabilities = vim.tbl_deep_extend("force", jdtls.extendedClientCapabilities, {
          resolveAdditionalTextEditsSupport = true,
        }),
      },
      settings = {
        java = {
          configuration = { runtimes = runtimes },
          signatureHelp = { enabled = true },
          -- Decompile library classes that ship without sources
          contentProvider = { preferred = "fernflower" },
          sources = {
            organizeImports = { starThreshold = 9999, staticStarThreshold = 9999 },
          },
        },
      },
      on_attach = function(_, bufnr)
        -- Registers the java-debug adapter with nvim-dap and pulls main
        -- classes in as launch configs, see configs/dap.lua for the keys.
        jdtls.setup_dap { hotcodereplace = "auto" }

        local map = vim.keymap.set
        local function opts(desc)
          return { buffer = bufnr, desc = desc }
        end

        map("n", "<leader>cjo", jdtls.organize_imports, opts "Java Organize Imports")
        map("n", "<leader>cjv", jdtls.extract_variable, opts "Java Extract Variable")
        map("n", "<leader>cjc", jdtls.extract_constant, opts "Java Extract Constant")
        map("v", "<leader>cjv", function()
          jdtls.extract_variable { visual = true }
        end, opts "Java Extract Variable")
        map("v", "<leader>cjm", function()
          jdtls.extract_method { visual = true }
        end, opts "Java Extract Method")
      end,
    }
  end

  vim.api.nvim_create_autocmd("FileType", { pattern = "java", callback = attach })

  -- ft = "java" means the FileType event that loaded this plugin has already
  -- fired, so the buffer that triggered it needs attaching by hand.
  if vim.bo.filetype == "java" then
    attach()
  end
end
