local h = dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/helpers.lua")
h.finish(function()
  vim.o.swapfile, vim.o.backup, vim.o.writebackup, vim.o.undofile = false, false, false, false
  vim.api.nvim_exec_autocmds("UIEnter", {})
  h.await(function()
    local clients = vim.lsp.get_clients({name="clangd"})
    return clients[1] and clients[1].initialized
  end,"clangd did not initialize")
  vim.wait(100)
  local cppbuf, source = vim.api.nvim_get_current_buf(), vim.api.nvim_buf_get_name(0)
  assert(vim.bo.filetype == "cpp")
  local mappings = {}
  for _, key in ipairs({" ds"," ch"," fm"," ct"," cs"," cr"," ca"," ce"," cx"," cu"," cd"," cb"," cR"," c?","<F9>",";"}) do
    local m = vim.fn.maparg(key,"n",false,true)
    mappings[key] = {rhs=m.rhs or "", desc=m.desc or "", buffer=m.buffer or 0, callback=m.callback ~= nil}
    assert(next(m),"missing mapping: " .. key)
  end
  h.write(h.root .. "/fixtures/full/check.rs","fn main() {}\n")
  vim.cmd.edit(vim.fn.fnameescape(h.root .. "/fixtures/full/check.rs"))
  for _, key in ipairs({" ca"," cd"," db"}) do
    local m = vim.fn.maparg(key,"n",false,true)
    mappings["rust" .. key] = {rhs=m.rhs or "", desc=m.desc or "", buffer=m.buffer or 0, callback=m.callback ~= nil}
    assert(m.buffer == 1 and m.desc:match("Rust") or m.desc == "Render Diagnostics")
  end
  assert(vim.fn.maparg(" cf","n") == "" and vim.fn.maparg(" cI","n") == "","C++ mappings leaked into Rust")
  vim.api.nvim_set_current_buf(cppbuf)
  local baseline = h.root .. "/reports/mappings-baseline.json"
  if vim.env.CP_CACHE_FULL_MODE == "baseline" then
    h.write(baseline,vim.json.encode(mappings)); print("P4 BASELINE PASS: full NvChad, clangd and preserved CPP/Rust mappings"); return
  end
  assert(vim.deep_equal(vim.json.decode(h.read(baseline)),mappings),"original mappings changed")
  local cache, a = require("cp_cache"), require("cp_cache.adapter")
  assert(cache.setup({cache_root=h.root .. "/store/full-" .. vim.uv.hrtime()}))
  local s = assert(cache.store())
  assert(s:save({id="cf-9000-X",name="full config sample",tests={{id=0,input="5\n1 2 3 4 5\n",output="15\n",origin="manual"},{id=2,input="3\n1 2 3\n",output="6\n"}}},0))
  assert(s:bind(source,"cf-9000-X"))
  assert(vim.fn.maparg(" cf","n") == "<Cmd>CPCache find<CR>")
  assert(vim.fn.maparg(" cI","n") == "<Cmd>CPCache info<CR>")
  assert(vim.tbl_contains(vim.fn.getcompletion("CPCache receive st","cmdline"),"stop"))
  if vim.env.CP_CACHE_FULL_MODE == "gdb" then dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/gdb.lua")(h,cppbuf,source); return end
  local before = h.snapshot(vim.fs.dirname(source))
  vim.cmd("CPTest release")
  local runner = assert(a.runners()[cppbuf]); h.done(runner)
  assert(runner.tcdata[1].exit_code == 0)
  for i=2,#runner.tcdata do assert(runner.tcdata[i].status == "CORRECT") end
  a.cleanup(cppbuf)
  vim.api.nvim_set_current_buf(cppbuf); vim.cmd("CPTest sanitize")
  runner = assert(a.runners()[cppbuf]); h.done(runner)
  for i=2,#runner.tcdata do assert(runner.tcdata[i].status == "CORRECT") end
  a.cleanup(cppbuf); vim.api.nvim_set_current_buf(cppbuf)
  vim.cmd("CompetiTest edit_testcase 0")
  h.map(vim.fn.bufnr("CompetiTestEditInput"),"<C-s>")
  assert(s:for_source(source).revision == 2)
  vim.cmd("CompetiTest convert files_to_singlefile | let g:cp_cache_bar = 1")
  assert(vim.g.cp_cache_bar == 1)
  local otherbuf, otherpath = h.source("full/renamed.cpp")
  cache.pick(otherbuf)
  h.await(function() return vim.bo.filetype == "TelescopePrompt" end,"real Telescope did not open")
  local prompt = vim.api.nvim_get_current_buf()
  h.await(function() return require("telescope.actions.state").get_selected_entry() ~= nil end,"Telescope selection unavailable")
  require("telescope.actions").select_default(prompt)
  h.await(function() return s:binding(otherpath) ~= nil end)
  assert(s:binding(otherpath).problem_id == "cf-9000-X")
  -- Only explicitly created source files are allowed in this directory.
  local after = h.snapshot(vim.fs.dirname(source)); after["renamed.cpp"] = nil
  assert(vim.deep_equal(before,after),"full config wrote files beside sources")
  dofile(vim.env.CP_CACHE_PLUGIN .. "/tests/debug_inputs.lua")(h,cppbuf,source)
  assert(vim.v.errmsg == "",vim.v.errmsg)
  print("P4 PASS: full NvChad/clangd, original CPP/Rust/DAP mappings, CPTest release/sanitize, real Telescope, compatible editor/export, no source pollution")
end)
