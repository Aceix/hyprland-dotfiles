-- Twilight lights up only the innermost block around the cursor (if/else,
-- loop, try, function, method, class, table/object literal, HTML/JSX
-- element, ...), found with
-- tree-sitter, however long it is. Where there's no block (top-level code, no
-- parser for the filetype) it's exactly RADIUS lines either side.
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

local function dim_colors(buf, top, bot)
  local from, to = { top, 0 }, { bot, -1 }
  local dimmed = {}
  for _, mark in ipairs(api.nvim_buf_get_extmarks(buf, twilight_ns, from, to, {})) do
    dimmed[mark[2]] = true
  end
  local own = saved[buf] or {}
  for name, ns in pairs(api.nvim_get_namespaces()) do
    if is_color_ns(name) then
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

return function(_, opts)
  require("twilight").setup(opts)
  local view = require "twilight.view"

  -- Loaded first so its provider, which (re)draws its colors, runs before ours
  require "vim.lsp.document_color"
  api.nvim_set_decoration_provider(api.nvim_create_namespace "twilight.colors", {
    on_win = function(_, _, buf, top, bot)
      if view.enabled or saved[buf] then -- after disabling: give the colors back
        dim_colors(buf, top, bot)
      end
    end,
  })
  api.nvim_create_autocmd("BufWipeout", {
    callback = function(ev)
      saved[ev.buf] = nil
    end,
  })

  -- line: 0-based cursor line. Returns the lit lines as 1-based [from, to).
  view.get_context = function(buf, line)
    local from, to = block_range(buf, line)
    if not from then
      from = math.max(0, line - RADIUS)
      to = math.min(api.nvim_buf_line_count(buf) - 1, line + RADIUS)
    end
    return from + 1, to + 2
  end
end
