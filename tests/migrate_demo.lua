local h = dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/helpers.lua")
h.finish(function()
  local cp = require("cp_cache")
  assert(cp.setup())
  local source = vim.fn.stdpath("config") .. "/examples/cp-demo/main.cpp"
  local before = h.snapshot(vim.fs.dirname(source))
  local buf = vim.fn.bufadd(source); vim.fn.bufload(buf); vim.bo[buf].filetype="cpp"
  local s = assert(cp.store())
  if not s:binding(source) then assert(cp.migrate(buf)) end
  local cases = assert(cp.get_testcases(buf)); assert(cases[1].output=="15\n" and cases[2].output=="6\n")
  assert(vim.deep_equal(before,h.snapshot(vim.fs.dirname(source))))
  print("P4 DEMO PASS: copied and verified existing examples; original files unchanged; cache " .. s.root)
end)
