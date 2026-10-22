-- Twilight lights up only the innermost block around the cursor (if/else,
-- loop, try, function, method, class, table/object literal, ...), found with
-- tree-sitter, however long it is. Where there's no block (top-level code, no
-- parser for the filetype) it's exactly RADIUS lines either side.
--
-- Upstream's context instead grows to the outermost node of a few literal
-- types ("function", "if_statement", ...) that most parsers don't use, or
-- else to ~10 lines snapped to blank lines. It also crashed on Neovim 0.12+,
-- where get_parser() returns nil rather than erroring for filetypes without
-- a parser (folke/twilight.nvim#54); here that's just the no-block case.
local RADIUS = 10

-- A node is a block when one of the _-separated words of its type is one of
-- these: if_statement, for_in_statement, arrow_function, method_definition,
-- table_constructor, closure_expression, impl_item, func_literal, ...
-- (elseif/elif/else branches aren't, so a whole if lights up)
local BLOCK = {}
for _, word in ipairs {
  "function", "func", "method", "constructor", "lambda", "closure",
  "class", "struct", "enum", "interface", "trait", "impl", "module", "namespace",
  "if", "unless", "for", "while", "until", "loop", "repeat", "do", "with",
  "try", "catch", "except", "switch", "select", "match", "when", "case",
  "table", "object", "array", "dictionary", "list",
} do
  BLOCK[word] = true
end
-- ...and none of these: a function_call or parameter list over several lines
-- isn't a block
local NOT_BLOCK = { call = true, invocation = true, arguments = true, parameters = true, signature = true }

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
  local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
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

return function(_, opts)
  require("twilight").setup(opts)

  -- line: 0-based cursor line. Returns the lit lines as 1-based [from, to).
  require("twilight.view").get_context = function(buf, line)
    local from, to = block_range(buf, line)
    if not from then
      from = math.max(0, line - RADIUS)
      to = math.min(vim.api.nvim_buf_line_count(buf) - 1, line + RADIUS)
    end
    return from + 1, to + 2
  end
end
