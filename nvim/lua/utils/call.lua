--- `call("mod", "fn", ...)` -> a function that runs `require("mod").fn(...)`.
--- For keymaps and lazy `keys`: the module only loads when the key is used.
--- The arguments are captured once, so every press gets the same values.
return function(mod, fn, ...)
  local args = vim.F.pack_len(...)
  return function()
    return require(mod)[fn](vim.F.unpack_len(args))
  end
end
