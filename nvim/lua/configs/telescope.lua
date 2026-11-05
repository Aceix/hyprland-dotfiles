-- Files and grep include hidden and git-ignored files, minus dependency
-- folders (utils/dep_dirs.lua); rg skips those itself, so it never walks them.
local dep_dirs = require "utils.dep_dirs"
local rg_args = dep_dirs.rg_args

-- grep fallback for live_grep/grep_string when rg is missing. Telescope appends
-- `[opts] -- <pattern> [dirs]` and parses file:line:col:text, so this wrapper
-- mimics rg: smart case, "." when no dirs are given, and a column of 1 (grep
-- has no --column), except for inverted (-v) searches, which have no column.
local grep_sh = [=[
k=0 inv=
for a do
  k=$((k + 1))
  case $a in --) break ;; -v | --invert-match) inv=1 ;; esac
done
eval "p=\${$((k + 1))}"
case $p in *[[:upper:]]*) i= ;; *) i=-i ;; esac
[ $# -le $((k + 1)) ] && set -- "$@" .
if [ -n "$inv" ]; then
  grep $i "$@"
else
  grep $i "$@" | sed 's/^\([^:]*:[0-9][0-9]*:\)/\11:/'
fi
]=]

return {
  defaults = {
    vimgrep_arguments = vim.fn.executable "rg" == 1
        and {
          "rg",
          "--color=never",
          "--no-heading",
          "--with-filename",
          "--line-number",
          "--column",
          "--smart-case",
          unpack(rg_args),
        }
      or { "sh", "-c", grep_sh, "sh", unpack(dep_dirs.grep_args) },
  },
  pickers = {
    find_files = {
      -- A function: find_files appends to the table it gets back
      -- Falls back to fd, then find: remote hosts often lack rg
      find_command = function()
        if vim.fn.executable "rg" == 1 then
          return { "rg", "--files", "--color=never", unpack(rg_args) }
        end
        for _, fd in ipairs { "fd", "fdfind" } do
          if vim.fn.executable(fd) == 1 then
            return { fd, unpack(dep_dirs.fd_args) }
          end
        end
        return { "find", unpack(dep_dirs.find_args) }
      end,
    },
  },
}
