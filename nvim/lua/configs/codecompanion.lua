local opts = {
  interactions = {
    chat = {
      adapter = "copilot",
      model = "gemini-3.1-pro",
      tools = {
        cmd_runner = { opts = { require_approval = true } },
        files = { opts = { require_approval = false } },
        buffer = { opts = { require_approval = false } },
      },
    },
    inline = {
      adapter = "copilot",
    },
    cmd = {
      adapter = "copilot",
    },
    background = {
      adapter = "copilot",
    },
  },

  extensions = {
    -- codecompanion-history.nvim: auto-saves chats; <leader>ah / `gh` in a chat
    history = {
      enabled = true,
      opts = {
        keymap = "gh",
        save_chat_keymap = "sc",
        auto_save = true,
        expiration_days = 0,
        picker = "telescope",
        auto_generate_title = true,
        continue_last_chat = true,
        delete_on_clearing_chat = false,
        dir_to_save = vim.fn.stdpath "data" .. "/codecompanion-history",
      },
    },
    mcphub = {
      callback = "mcphub.extensions.codecompanion",
      opts = {
        make_tools = true,
        show_server_tools_in_chat = true,
        add_mcp_prefix_to_tool_names = false,
        show_result_in_chat = true,
        -- mcphub still registers resources into interactions.chat.variables,
        -- which CodeCompanion v19 renamed to editor_context; it crashes on nil.
        -- Re-enable once mcphub supports editor_context.
        make_vars = false,
        make_slash_commands = true,
      },
    },
  },
}


-- mcphub is local-only (configs/lazy.lua): it can't attach to the laptop's hub
-- through a tunnel, it would hard-restart it and spawn its own on the remote.
if require("utils.remote").is_remote then
  opts.extensions.mcphub = nil
end

return opts
