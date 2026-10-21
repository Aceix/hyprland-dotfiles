require "nvchad.options"

local o = vim.o

o.cursorlineopt = 'both' -- to enable cursorline!

vim.opt.relativenumber = true -- (NvChad already turns on number)

-- Use Treesitter syntax parsing engine to calculate code folds
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"

-- Prevent Neovim from opening files with everything automatically folded closed
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99

vim.opt.wrap = false

vim.opt.equalalways = false  -- Forces Neovim to leave existing layouts exactly as they are

-- VS Code-style diffs (diffview, the sidebar's diff, :diffsplit): highlight
-- the exact changed characters inside a changed line, and pair up edited /
-- moved lines across larger hunks. Needs Neovim 0.12+ for "inline:".
vim.opt.diffopt:remove "linematch:40" -- (inline:char is already the default)
vim.opt.diffopt:append "linematch:60"

-- VS Code-style selection: a shifted cursor key starts a charwise Visual
-- selection and, while Shift stays held, EXTENDS it instead of starting over.
-- Covers <S-Left/Right/Up/Down/Home/End> from normal, visual and insert mode.
-- 'selectmode' stays at its default (empty) so these start Visual mode, not
-- Select mode.
-- Add "stopsel" too if you also want a plain (un-shifted) arrow to drop the
-- selection the way VS Code does.
vim.opt.keymodel = "startsel"

-- Session (persistence.nvim) contents. The default 'sessionoptions' includes
-- "buffers", which makes :mksession record *every* listed buffer -- including
-- hidden/unloaded ones -- so a file closed mid-session would reopen on the next
-- launch. Dropping "buffers" persists only the buffers visible in a window at
-- quit time; close a buffer and it stays closed. ("blank"/"terminal" are also
-- dropped: empty and terminal windows are torn down in PersistenceSavePre.)
vim.opt.sessionoptions = "curdir,folds,help,tabpages,winsize"

