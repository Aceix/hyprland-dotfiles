-- Add / delete / replace surrounding pairs. On `gs`, since `s` is flash's:
-- gsaiw" add, gsd" delete, gsr"' replace, gsf / gsF find, gsh highlight
return {
  "nvim-mini/mini.surround",
  keys = {
    { "gs", "", desc = "+surround" },
    { "gsa", mode = { "n", "x" }, desc = "Add Surrounding" },
    { "gsd", desc = "Delete Surrounding" },
    { "gsr", desc = "Replace Surrounding" },
    { "gsf", desc = "Find Right Surrounding" },
    { "gsF", desc = "Find Left Surrounding" },
    { "gsh", desc = "Highlight Surrounding" },
    { "gsn", desc = "Surround: Update n_lines" },
  },
  opts = {
    mappings = {
      add = "gsa",
      delete = "gsd",
      replace = "gsr",
      find = "gsf",
      find_left = "gsF",
      highlight = "gsh",
      update_n_lines = "gsn",
    },
  },
}
