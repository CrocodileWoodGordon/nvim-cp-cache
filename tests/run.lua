local h = dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/helpers.lua")
h.finish(function()
  for _, suite in ipairs({"store", "workflow", "receiver", "acceptance"}) do
    if not vim.env.CP_CACHE_SUITE or vim.env.CP_CACHE_SUITE == suite then dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/" .. suite .. ".lua")(h) end
  end
end)
