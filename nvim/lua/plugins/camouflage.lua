-- Masks secret values on screen (screen sharing, pairing); the file itself is
-- untouched. <leader>us toggles it. Only in files that are nothing but
-- secrets: its defaults also cover every JSON / YAML / TOML / shell file and
-- switch completion off in them.
--
-- Loaded right after startup rather than with the first secret file: it also
-- masks Telescope previews, grep result rows, quickfix lists and git diffs,
-- which show a secret file's contents before it was ever opened. (The files
-- themselves still load it early, for `nvim .env`.)
local files = { ".env", ".env.*", "*.env", ".envrc", "credentials", ".netrc", "*.tfvars" }

local function events(event)
  return vim.tbl_map(function(pattern)
    return { event = event, pattern = pattern }
  end, files)
end

return {
  "zeybek/camouflage.nvim",
  event = vim.list_extend({ "VeryLazy" }, vim.list_extend(events "BufReadPre", events "BufNewFile")),
  cmd = { "CamouflageToggle", "CamouflageReveal", "CamouflageYank", "CamouflageStatus", "CamouflageAudit" },
  keys = {
    { "<leader>uR", "<cmd>CamouflageReveal<cr>", desc = "Reveal Secrets on This Line" },
  },
  opts = {
    patterns = {
      { file_pattern = { ".env", ".env.*", "*.env", ".envrc" }, parser = "env" },
      { file_pattern = { "credentials" }, parser = "properties" },
      { file_pattern = { ".netrc" }, parser = "netrc" },
      { file_pattern = { "*.tfvars" }, parser = "hcl" },
    },
    -- Its completion switch would load blink.cmp (and LuaSnip) at startup;
    -- utils/sensitive.lua turns completion off in these files instead
    integrations = {
      blink = { disable_in_masked = false },
      cmp = { disable_in_masked = false },
    },
  },
  config = function(_, opts)
    require("camouflage").setup(opts)

    -- The first time a file's secrets get masked, say how to see them
    -- (picker previews are scratch buffers: no hint there)
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("CamouflageHint", { clear = true }),
      pattern = "CamouflageAfterDecorate",
      callback = function(ev)
        local data = ev.data or {}
        local buf = data.bufnr
        if
          not (buf and vim.api.nvim_buf_is_valid(buf))
          or vim.bo[buf].buftype ~= ""
          or vim.b[buf].camouflage_hinted
          or not next(data.variables or {})
        then
          return
        end
        vim.b[buf].camouflage_hinted = true
        vim.notify(
          "Secret values in this file are hidden.\n"
            .. "Space u R   show / hide the ones on the cursor's line\n"
            .. "Space u s   show / hide all of them",
          vim.log.levels.INFO,
          { title = "Secrets" }
        )
      end,
    })
  end,
}
