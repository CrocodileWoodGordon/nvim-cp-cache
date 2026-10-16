local h = dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/helpers.lua")
local a = require("cp_cache.adapter")
h.finish(function()
  local buf = h.source("probe/main.cpp")
  local runner = a.new_runner(buf)
  runner:set_restore_winid(vim.api.nvim_get_current_win())
  runner:run_testcases({ [0] = { input = "5\n1 2 3 4 5\n", output = "15\n" },
    [2] = { input = "3\n1 2 3\n", output = "6\n" } }, true)
  runner:show_ui()
  h.await(function()
    for _, tc in pairs(runner.tcdata) do if tc.status == "RUNNING" or tc.status == "" then return false end end
    return true
  end, "runner did not complete", 30000)
  for _, tc in pairs(runner.tcdata) do
    assert(tc.tcnum == "Compile" and tc.exit_code == 0 or tc.status == "CORRECT", vim.inspect(tc))
  end
  runner.ui:hide_ui(); assert(not runner.ui.ui_visible)
  runner:show_ui(); assert(runner.ui.ui_visible)
  a.resize(); vim.wait(100)
  runner.ui:hide_ui()
  local calls, saved = 0
  a.editor_widget(buf, 0, "中文\r\n\n", "", function(tc) calls, saved = calls + 1, tc end)
  local editbuf = vim.fn.bufnr("CompetiTestEditInput")
  h.map(editbuf, "<C-s>")
  assert(calls == 1 and saved.input == "中文\r\n\n" and saved.output == "", vim.inspect(saved))
  a.editor_widget(buf, 0, "cancel", nil, function() calls = calls + 1 end)
  h.map(vim.fn.bufnr("CompetiTestEditInput"), "q")
  assert(calls == 1, "cancel must not call save")
  a.cleanup(buf); assert(a.runners()[buf] == nil)
  assert(not vim.uv.fs_stat(h.root .. "/fixtures/probe/testcases"))
  print("P0 PASS: real CompetiTest compile, cases 0/2, editor save/cancel, hide/reopen/resize/delete")
end)
