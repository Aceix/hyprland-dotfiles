-- Rust: rust-analyzer, codelldb and cargo's tests (lua/langs/rust.lua
-- installs the first two). Configured through vim.g.rustaceanvim only; never
-- enable lspconfig's rust_analyzer next to it.
return {
  "mrcjkb/rustaceanvim",
  version = "^9",
  ft = "rust",
  init = function()
    vim.g.rustaceanvim = {
      server = {
        on_attach = function(_, buf)
          local function map(lhs, action, desc)
            vim.keymap.set("n", "<leader>cj" .. lhs, function()
              vim.cmd.RustLsp(action)
            end, { buffer = buf, desc = "Rust: " .. desc })
          end
          map("r", "runnables", "Runnables")
          map("d", "debuggables", "Debuggables")
          map("m", "expandMacro", "Expand Macro")
          map("e", "explainError", "Explain Error")
          map("p", "parentModule", "Parent Module")
          map("c", "openCargo", "Open Cargo.toml")
        end,
        default_settings = {
          ["rust-analyzer"] = {
            check = { command = "clippy" },
            cargo = { allFeatures = true },
          },
        },
      },
    }
  end,
}
