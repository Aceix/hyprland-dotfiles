-- Jupyter REPL (<leader>N): run lines, selections or text objects against a
-- kernel, output shown under the code. Run :MoltenSetup once
-- (configs/molten.lua has the why).
return {
  "benlubas/molten-nvim",
  version = "^1",
  build = function()
    require("configs.molten").update()
  end,
  cmd = {
    "MoltenInit", "MoltenInfo", "MoltenEvaluateLine", "MoltenEvaluateVisual", "MoltenEvaluateOperator",
    "MoltenReevaluateCell", "MoltenDelete", "MoltenInterrupt", "MoltenRestart", "MoltenShowOutput",
    "MoltenHideOutput", "MoltenEnterOutput", "MoltenDeinit",
  },
  keys = {
    { "<leader>N", "", mode = { "n", "x" }, desc = "+notebook (jupyter)" },
    { "<leader>Ni", "<cmd>MoltenInit<cr>", desc = "Notebook: Start Kernel" },
    { "<leader>Ne", "<cmd>MoltenEvaluateOperator<cr>", desc = "Notebook: Run (operator)" },
    { "<leader>Nl", "<cmd>MoltenEvaluateLine<cr>", desc = "Notebook: Run Line" },
    { "<leader>Nv", ":<C-u>MoltenEvaluateVisual<cr>gv", mode = "x", desc = "Notebook: Run Selection" },
    { "<leader>Nr", "<cmd>MoltenReevaluateCell<cr>", desc = "Notebook: Re-run Cell" },
    { "<leader>No", "<cmd>noautocmd MoltenEnterOutput<cr>", desc = "Notebook: Open Output" },
    { "<leader>Nd", "<cmd>MoltenDelete<cr>", desc = "Notebook: Delete Cell" },
    { "<leader>Nx", "<cmd>MoltenInterrupt<cr>", desc = "Notebook: Interrupt Kernel" },
  },
  init = function()
    vim.api.nvim_create_user_command("MoltenSetup", function()
      require("configs.molten").setup_venv()
    end, { desc = "Create the Python venv molten-nvim (Jupyter) runs in" })

    vim.g.molten_image_provider = "none"
    vim.g.molten_auto_open_output = false
    vim.g.molten_virt_text_output = true
    vim.g.molten_virt_lines_off_by_1 = true
    vim.g.molten_output_win_max_height = 20
  end,
  config = function()
    require("configs.molten").enable()
  end,
}
