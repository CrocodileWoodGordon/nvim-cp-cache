local h = dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/helpers.lua")
h.finish(function()
  dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/store.lua")(h)
end)
