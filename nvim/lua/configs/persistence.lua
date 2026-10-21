-- persistence.nvim opts. The current plugin API only understands `dir`, `need`
-- and `branch`; session *contents* are controlled by 'sessionoptions', set in
-- lua/options.lua (that's where "buffers" is dropped so closed files don't
-- reopen). An older API used an `options` table here -- it is now ignored.
return {}
