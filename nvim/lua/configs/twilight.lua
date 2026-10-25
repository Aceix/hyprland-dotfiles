-- Twilight lights up only the innermost block around the cursor (if/else,
-- loop, try, function, method, class, table/object literal, HTML/JSX
-- element, ...), found with
-- tree-sitter, however long it is. Where there's no block (top-level code, no
-- parser for the filetype) it's exactly RADIUS lines either side. In visual
-- mode every selected line lights up too.
--
-- Upstream's context instead grows to the outermost node of a few literal
-- types ("function", "if_statement", ...) that most parsers don't use, or
-- else to ~10 lines snapped to blank lines. It also crashed on Neovim 0.12+,
-- where get_parser() returns nil rather than erroring for filetypes without
-- a parser (folke/twilight.nvim#54); here that's just the no-block case.
local api = vim.api
local RADIUS = 10

-- A node is a block when one of the _-separated words of its type is one of
-- these: if_statement, for_in_statement, arrow_function, method_definition,
-- table_constructor, closure_expression, impl_item, func_literal, element,
-- jsx_element, jsx_self_closing_element, ...
-- (elseif/elif/else branches aren't, so a whole if lights up)
local function set(words)
  local out = {}
  for _, word in ipairs(words) do
    out[word] = true
  end
  return out
end

local BLOCK = set {
  "function", "func", "method", "constructor", "lambda", "closure",
  "class", "struct", "enum", "interface", "trait", "impl", "module", "namespace",
  "if", "unless", "for", "while", "until", "loop", "repeat", "do", "with",
  "try", "catch", "except", "switch", "select", "match", "when", "case",
  "table", "object", "array", "dictionary", "list", "element", "fragment",
}
-- ...and none of these: a function_call, parameter list or JSX opening tag
-- over several lines isn't a block (the tag's element is)
local NOT_BLOCK = set { "call", "invocation", "arguments", "parameters", "signature", "opening" }

local function is_block(type)
  local block = false
  for word in type:gmatch "[^_]+" do
    if NOT_BLOCK[word] then
      return false
    end
    block = block or BLOCK[word] == true
  end
  return block
end

-- 0-based first and last line of the innermost block around col that spans
-- more than the line itself. Injected code (a fenced block in markdown, ...)
-- is searched first, then the language around it.
local function block_at(parser, line, col)
  local range = { line, col, line, col }
  local tree = parser:language_for_range(range)
  while tree do
    local node = tree:named_node_for_range(range, { ignore_injections = true })
    while node do
      local from, _, to, to_col = node:range()
      if to_col == 0 and to > from then
        to = to - 1 -- ends at the start of the next line
      end
      if to > from and is_block(node:type()) then
        if node:type() == "pipe_table" then
          -- render-markdown draws a table's top and bottom borders over the
          -- blank lines either side of it
          return math.max(0, from - 1), to + 1
        end
        return from, to
      end
      node = node:parent()
    end
    tree = tree:parent()
  end
end

-- The innermost block seen from the line's first or last character, so a
-- block's opening line (`local t = {`, `if x then`) and closing line (`})`,
-- `end`) both light up that block
local function block_range(buf, line)
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not (ok and parser) then
    return
  end
  local text = api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
  parser:parse { line, line + 1 }
  local first = math.max(0, (text:find "%S" or 1) - 1)
  local last = math.max(0, (text:find "%S%s*$" or 1) - 1)
  local from, to = block_at(parser, line, first)
  if last ~= first then
    local lfrom, lto = block_at(parser, line, last)
    if lfrom and (not from or lto - lfrom < to - from) then
      from, to = lfrom, lto
    end
  end
  return from, to
end

-- Colors drawn into the text (Tailwind classes, hex codes, ...: NvChad's
-- colorify swatches and Neovim's LSP document colors) aren't dimmed by
-- twilight, and with a transparent background its guibg=NONE can't cover
-- them. So on every redraw the color marks on dimmed lines are recolored
-- Twilight, and given their colors back once lit. At draw time, because those
-- plugins (re)color whenever an LSP reply comes in.
local twilight_ns = api.nvim_create_namespace "twilight"
local saved = {} -- buf -> "ns:id" -> the color mark's own highlight group

local function is_color_ns(name)
  return name == "Colorify" or vim.startswith(name, "nvim.lsp.document_color:")
end

-- A color mark has one highlight: its hl_group, or else its swatch's
local function get_hl(opts)
  return opts.hl_group or opts.virt_text[1][2]
end

local function set_hl(opts, hl)
  if opts.hl_group then
    opts.hl_group = hl
  else
    opts.virt_text[1][2] = hl
  end
end

-- render-markdown draws tables (borders, pipes, the delimiter row), heading
-- icons, bullets, code block borders, ... as virtual text and virtual lines,
-- which carry their own highlights and so aren't dimmed by twilight's
-- hl_group either. A chunk's highlight can be a stack of groups, so on dimmed
-- lines Twilight is pushed on top of each chunk's own highlight and popped
-- once lit: the mark keeps its own look, and nothing is keyed by mark id,
-- which render-markdown's constant redraws (and Neovim) reuse. A virtual line
-- is dimmed with the line it hangs off.
local markdown_ns = "render-markdown.nvim"

local function is_dimmed(chunk)
  local hl = chunk[2]
  return type(hl) == "table" and hl[#hl] == "Twilight"
end

local function set_dimmed(chunk, dim)
  local hl = chunk[2]
  hl = type(hl) == "table" and vim.list_slice(hl) or { hl }
  if dim then
    hl[#hl + 1] = "Twilight"
  else
    hl[#hl] = nil
  end
  chunk[2] = hl
end

local function dim_markdown(buf, ns, from, to, dimmed)
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, from, to, { details = true })) do
    local id, row, col, opts = unpack(mark)
    local lines = opts.virt_lines or { opts.virt_text }
    local dim = dimmed[row] == true
    local first = lines[1] and lines[1][1]
    if first and dim ~= is_dimmed(first) then
      for _, line in ipairs(lines) do
        for _, chunk in ipairs(line) do
          set_dimmed(chunk, dim)
        end
      end
      opts.ns_id, opts.id = nil, id
      pcall(api.nvim_buf_set_extmark, buf, ns, row, col, opts)
    end
  end
end

local function dim_marks(buf, top, bot)
  local from, to = { top, 0 }, { bot, -1 }
  local dimmed = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, twilight_ns, from, to, {})) do
    dimmed[mark[2]] = true
  end
  local own = saved[buf] or {}
  for name, ns in pairs(api.nvim_get_namespaces()) do
    if name == markdown_ns then
      dim_markdown(buf, ns, from, to, dimmed)
    elseif is_color_ns(name) then
      for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, ns, from, to, { details = true })) do
        local id, row, col, opts = unpack(mark)
        local hl = get_hl(opts)
        local dim = dimmed[row] == true
        if dim ~= (hl == "Twilight") then
          local key = ns .. ":" .. id
          if dim then
            own[key], hl = hl, "Twilight"
          else
            hl, own[key] = own[key], nil
          end
          if hl then
            set_hl(opts, hl)
            opts.ns_id, opts.id = nil, id
            pcall(api.nvim_buf_set_extmark, buf, ns, row, col, opts)
          end
        end
      end
    end
  end
  saved[buf] = next(own) and own or nil
end

-- v, V and Ctrl-V
local function is_visual(mode)
  return mode:find "^[vV\22]" ~= nil
end

return function(_, opts)
  require("twilight").setup(opts)
  local view = require "twilight.view"

  -- Disabling clears every buffer's dimming, so give every mark its look back
  local disable = view.disable
  view.disable = function()
    disable()
    for _, buf in ipairs(api.nvim_list_bufs()) do
      if api.nvim_buf_is_loaded(buf) then
        dim_marks(buf, 0, -1)
      end
    end
  end

  -- Loaded first so its provider, which (re)draws its colors, runs before ours
  require "vim.lsp.document_color"
  -- The marks are recolored right after the redraw, not during it: a mark
  -- changed mid-redraw only shows on the lines not drawn yet, and nothing
  -- repaints the rest. Changing a mark afterwards repaints its line, which
  -- runs on_win again; that pass finds nothing to change and so stops.
  local pending = {} -- win -> a recolor is scheduled
  api.nvim_set_decoration_provider(api.nvim_create_namespace "twilight.marks", {
    on_win = function(_, win, buf, top, bot)
      if view.enabled and not pending[win] then
        pending[win] = true
        vim.schedule(function()
          pending[win] = nil
          if api.nvim_buf_is_valid(buf) then
            dim_marks(buf, top, bot)
          end
        end)
      end
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    callback = function(ev)
      saved[ev.buf] = nil
    end,
  })
  -- Twilight only updates on cursor moves, so v or <Esc> alone would leave the
  -- lit lines stale
  api.nvim_create_autocmd("ModeChanged", {
    callback = function()
      local ev = vim.v.event
      if view.enabled and is_visual(ev.old_mode) ~= is_visual(ev.new_mode) then
        view.update()
      end
    end,
  })

  -- line: 0-based cursor line. Returns the lit lines as 1-based [from, to).
  view.get_context = function(buf, line)
    local from, to = block_range(buf, line)
    if not from then
      from = math.max(0, line - RADIUS)
      to = math.min(api.nvim_buf_line_count(buf) - 1, line + RADIUS)
    end
    -- The block holds the cursor line, so only the selection's other end can
    -- reach past it
    if buf == api.nvim_get_current_buf() and is_visual(api.nvim_get_mode().mode) then
      local anchor = vim.fn.line "v" - 1
      from, to = math.min(from, anchor), math.max(to, anchor)
    end
    return from + 1, to + 2
  end
end
