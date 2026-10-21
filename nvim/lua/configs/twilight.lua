return function(_, opts)
  require("twilight").setup(opts)

  -- Upstream bug (folke/twilight.nvim#54, fix not yet merged): on Neovim
  -- 0.12+, vim.treesitter.get_parser() returns nil instead of erroring
  -- for filetypes with no installed parser. get_context()'s guard here
  -- only checked that the call didn't error (pcall ok), not that it
  -- actually got a parser, so it stayed on the treesitter path with a
  -- nil parser: get_node() crashed on CursorMoved, and once patched to
  -- no-op instead, context collapsed to just the current line because
  -- the intended fallback (a +/- context/2 line window expanded to
  -- blank-line boundaries, below) was unreachable. Checking `parser`
  -- itself (matching upstream PR #55) restores that fallback for
  -- parser-less filetypes while leaving unaffected filetypes that do
  -- have a parser installed, which still get full block/function nodes.
  local view = require "twilight.view"
  local config = require "twilight.config"

  view.get_context = function(buf, line)
    local ok, parser = pcall(vim.treesitter.get_parser, buf)
    if config.options.treesitter and ok and parser then
      local node = view.get_node(buf, line)
      local root = view.get_expand_root(node)
      if root then
        local from, to = view.range(root)
        return from + 1, to + 2
      end
      local from, to = view.expand(buf, line, line, line)

      while to - from < config.options.context do
        local pf, pt, pnode = view.expand(buf, from, to, from - 1)
        local nf, nt, nnode = view.expand(buf, from, to, to + 1)

        local mp = math.max(line - pf, pt - line)
        local mn = math.max(line - nf, nt - line)

        if (mp < mn) and not (from == pf and to == pt) then
          from = pf
          to = pt
          if pnode and view.get_expand_root(pnode) then break end
        elseif not (from == nf and to == nt) then
          from = nf
          to = nt
          if nnode and view.get_expand_root(nnode) then break end
        else
          break
        end
      end

      return from + 1, to + 2
    end

    local from = line - math.floor(config.options.context / 2)
    local to = line + math.floor(config.options.context / 2)

    local lcount = vim.api.nvim_buf_line_count(buf)
    if to > lcount then to = lcount end
    if from < 1 then from = 1 end

    while from > 0 and not view.is_empty(buf, from) do
      from = from - 1
    end
    while to < lcount and not view.is_empty(buf, to) do
      to = to + 1
    end

    return from + 1, to + 2
  end
end
