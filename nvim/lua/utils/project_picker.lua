-- project.nvim's own Telescope extension (`:Telescope projects`) opens a
-- find_files picker on <CR> after switching directory. We want selecting a
-- project to instead drop all buffers and show a fresh NvChad dashboard,
-- like nvim just restarted inside that project -- that action isn't
-- something the extension exposes, so it's reimplemented here.
local M = {}

function M.switch_project()
  local pickers = require "telescope.pickers"
  local finders = require "telescope.finders"
  local telescope_config = require("telescope.config").values
  local actions = require "telescope.actions"
  local action_state = require "telescope.actions.state"
  local entry_display = require "telescope.pickers.entry_display"
  local history = require "project_nvim.utils.history"
  local project = require "project_nvim.project"

  local results = history.get_recent_projects()
  for i = 1, math.floor(#results / 2) do
    results[i], results[#results - i + 1] = results[#results - i + 1], results[i]
  end

  local displayer = entry_display.create {
    separator = " ",
    items = { { width = 30 }, { remaining = true } },
  }

  pickers
    .new({}, {
      prompt_title = "Switch Project",
      previewer = false,
      finder = finders.new_table {
        results = results,
        entry_maker = function(entry)
          local name = vim.fn.fnamemodify(entry, ":t")
          return {
            display = function(e) return displayer { e.name, { e.value, "Comment" } } end,
            name = name,
            value = entry,
            ordinal = name .. " " .. entry,
          }
        end,
      },
      sorter = telescope_config.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if not selection then return end

          project.set_pwd(selection.value, "telescope")
          vim.cmd "silent! %bdelete!"
          require("nvchad.nvdash").open()
        end)
        return true
      end,
    })
    :find()
end

return M
