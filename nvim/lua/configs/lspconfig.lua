require("nvchad.configs.lspconfig").defaults()

-- Servers start per buffer only: `vim.lsp.enable` registers a FileType hook,
-- and each config's root_markers keep e.g. angularls/svelte/tailwindcss out of
-- projects that don't use them. Configs come from nvim-lspconfig's lsp/*.lua;
-- the vim.lsp.config() calls below only layer settings on top.

-- Vue LS v3 has no takeover mode: it handles template/style itself and forwards
-- every TypeScript request in a .vue file to vtsls, which needs the Vue TS
-- plugin loaded and `vue` in its filetypes. Without this, gd/hover/rename in
-- <script> and template expressions return nothing.
local vue_plugin = vim.fn.stdpath "data"
  .. "/mason/packages/vue-language-server/node_modules/@vue/language-server"

local ts_inlay_hints = {
  parameterNames = { enabled = "literals" },
  parameterTypes = { enabled = true },
  variableTypes = { enabled = false },
  propertyDeclarationTypes = { enabled = true },
  functionLikeReturnTypes = { enabled = true },
  enumMemberValues = { enabled = true },
}

vim.lsp.config("vtsls", {
  filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact", "vue" },
  settings = {
    vtsls = {
      autoUseWorkspaceTsdk = true,
      tsserver = {
        globalPlugins = {
          {
            name = "@vue/typescript-plugin",
            location = vue_plugin,
            languages = { "vue" },
            configNamespace = "typescript",
            enableForWorkspaceTypeScriptVersions = true,
          },
        },
      },
    },
    typescript = {
      inlayHints = ts_inlay_hints,
      updateImportsOnFileMove = { enabled = "always" },
      tsserver = { maxTsServerMemory = 4096 },
    },
    javascript = {
      inlayHints = ts_inlay_hints,
      updateImportsOnFileMove = { enabled = "always" },
    },
  },
})

vim.lsp.config("gopls", {
  settings = {
    gopls = {
      gofumpt = true,
      usePlaceholders = true,
      completeUnimported = true,
      staticcheck = true,
      analyses = { unusedparams = true, unusedwrite = true, nilness = true },
      hints = {
        assignVariableTypes = true,
        compositeLiteralFields = true,
        constantValues = true,
        functionTypeParameters = true,
        parameterNames = true,
        rangeVariableTypes = true,
      },
    },
  },
})

-- Python: basedpyright for types/completion/navigation, ruff for lint and
-- quick fixes. Pointing pyright at the project venv (utils/python.lua) means
-- imports resolve without activating it; import sorting is left to ruff.
vim.lsp.config("basedpyright", {
  before_init = function(_, config)
    config.settings.python = vim.tbl_extend("force", config.settings.python or {}, {
      pythonPath = require("utils.python").path(config.root_dir),
    })
  end,
  settings = {
    basedpyright = {
      disableOrganizeImports = true,
      analysis = {
        -- "recommended" (basedpyright's default) flags almost every untyped
        -- call; "standard" matches what Pylance shows in VS Code
        typeCheckingMode = "standard",
      },
    },
  },
})

-- SchemaStore.nvim: package.json, tsconfig, GitHub Actions, docker-compose, ...
vim.lsp.config("jsonls", {
  settings = {
    json = { schemas = require("schemastore").json.schemas(), validate = { enable = true } },
  },
})

vim.lsp.config("yamlls", {
  settings = {
    yaml = {
      -- the built-in store is replaced by SchemaStore.nvim's copy
      schemaStore = { enable = false, url = "" },
      schemas = require("schemastore").yaml.schemas(),
      keyOrdering = false,
    },
  },
})

-- ships with root_markers but would still start rootless in every .ts/.html
vim.lsp.config("angularls", { workspace_required = true })

-- lspconfig falls back to any `.git` root (for Tailwind v4), which starts it in
-- every web repo. Only start where a tailwind config or a package.json that
-- mentions `tailwindcss` exists (nearest-first, so monorepo roots count).
vim.lsp.config("tailwindcss", {
  root_dir = function(bufnr, on_dir)
    local fname = vim.api.nvim_buf_get_name(bufnr)
    local cfg = vim.fs.find(function(name)
      return name:match "^tailwind%.config%." ~= nil
    end, { path = fname, upward = true })[1]
    if cfg then
      return on_dir(vim.fs.dirname(cfg))
    end
    for _, pkg in ipairs(vim.fs.find("package.json", { path = fname, upward = true, limit = math.huge })) do
      local f = io.open(pkg)
      local body = f and f:read "*a" or ""
      if f then
        f:close()
      end
      if body:find('"tailwindcss"', 1, true) or body:find('"@tailwindcss/', 1, true) then
        return on_dir(vim.fs.dirname(pkg))
      end
    end
  end,
})

-- Fix-all-on-demand only; formatting stays with prettier (configs/conform.lua)
vim.lsp.config("eslint", {
  settings = { workingDirectories = { mode = "auto" } },
})

vim.lsp.enable {
  -- Go
  "gopls",
  "golangci_lint_ls",
  -- TS/JS, React/Next, Vue/Nuxt, Svelte, Angular
  "vtsls",
  "vue_ls",
  "svelte",
  "angularls",
  "eslint",
  -- Web
  "html",
  "cssls",
  "tailwindcss",
  "emmet_language_server",
  -- Data / config
  "jsonls",
  "yamlls",
  "lemminx",
  "dockerls",
  -- Python
  "basedpyright",
  "ruff",
  -- WebAssembly text (.wat / .wast)
  "wasm_language_tools",
}
-- Java is started per project by nvim-jdtls (plugins/jdtls.lua), not here.

vim.api.nvim_create_autocmd("LspAttach", {
  group = vim.api.nvim_create_augroup("UserLspAttach", { clear = true }),
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
      return
    end
    -- ruff's hover is only rule docs; let basedpyright answer K in Python
    if client.name == "ruff" then
      client.server_capabilities.hoverProvider = false
    end
    if client:supports_method "textDocument/inlayHint" then
      vim.lsp.inlay_hint.enable(true, { bufnr = args.buf })
    end
  end,
})
