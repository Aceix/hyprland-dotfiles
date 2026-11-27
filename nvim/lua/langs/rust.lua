-- Rust. rustaceanvim (plugins/rustaceanvim.lua) starts rust-analyzer itself
-- and wires up codelldb and the test adapter, so there's no `lsp` entry;
-- formatting is rust-analyzer's (rustfmt) through <leader>cf's fallback.
return {
  mason = { "rust-analyzer", "codelldb" },
  parsers = { "rust", "toml" },

  neotest = {
    detect = function(cwd)
      return vim.uv.fs_stat(cwd .. "/Cargo.toml") ~= nil
    end,
    adapters = function()
      return { require "rustaceanvim.neotest" }
    end,
  },

  deps = function(d)
    return {
      test = { rust = { label = "Rust tests", d.exe("cargo", "install Rust (rustup)") } },
    }
  end,
}
