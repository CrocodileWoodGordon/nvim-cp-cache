return function(h)
  local cp, a = require("cp_cache"), require("cp_cache.adapter")
  assert(cp.setup({cache_root=h.root .. "/store/acceptance-" .. vim.uv.hrtime()}))
  local s = assert(cp.store())
  local buf, source = h.source("acceptance/" .. vim.uv.hrtime() .. "/main.cpp",'#include <iostream>\nint main(){std::cout<<"wrong\\n";}\n')
  local before = h.snapshot(vim.fs.dirname(source))
  local p = assert(s:save({id="cf-8000-A",name="acceptance",tests={{id=0,input="",output="correct\n",origin="manual"},{id=2,input="",output="correct\n"}}},0))
  assert(s:bind(source,p.id))
  local r = assert(cp.run(buf)); h.done(r); assert(r.tcdata[2].status == "WRONG" and r.tcdata[3].status == "WRONG")
  a.cleanup(buf); vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf,0,-1,false,{"this is not C++"})
  r = assert(cp.run(buf))
  h.await(function() return r.tcdata[1].exit_code ~= nil end,"compiler failure missing",30000)
  assert(r.tcdata[1].exit_code ~= 0 and not r.tcdata[2].process and not r.tcdata[3].process,"failed compile ran old executable")
  a.cleanup(buf); vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf,0,-1,false,{"int main(){while(true) {}}"})
  a.setup_dependency({maximum_time=150})
  r = assert(cp.run(buf))
  h.await(function() return r.tcdata[2].running end,"slow case never started",30000)
  h.map(r.ui.windows.tc.bufnr,"<C-k>")
  h.await(function() return r.tcdata[2].status == "KILLED" end,"kill failed")
  assert(not r.tcdata[3].process,"kill_all started queued case")
  vim.api.nvim_set_current_win(r.ui.windows.tc.winid)
  h.map(r.ui.windows.tc.bufnr,"<C-r>"); vim.wait(30)
  r=assert(a.runners()[buf]); h.done(r)
  assert(r.tcdata[2].status == "TIMEOUT" and r.tcdata[3].status == "TIMEOUT")
  r.ui:hide_ui(); assert(cp.run(buf,{only_show=true}) == r); a.resize(); vim.wait(50)
  r=assert(cp.run(buf,{compile=false})); h.await(function() return r.tcdata[1].running end)
  local active_pid = r.tcdata[1].process.pid
  vim.api.nvim_set_current_win(vim.fn.bufwinid(buf)); vim.api.nvim_buf_delete(buf,{force=true})
  h.await(function() return not a.runners()[buf] and not r.tcdata[1].running end,"buffer unload left process/UI")
  local live=vim.uv.kill(active_pid,0); assert(not live,"process survived buffer unload")
  assert(not r.ui.ui_visible)
  -- Source content was explicitly changed by this test; every other directory entry must match.
  local after=h.snapshot(vim.fs.dirname(source)); before["main.cpp"],after["main.cpp"]=nil,nil
  assert(vim.deep_equal(before,after))
  a.setup_dependency({maximum_time=3000})
  local other, otherpath=h.source("acceptance/share/" .. vim.uv.hrtime() .. "/B.cpp")
  assert(s:bind(otherpath,p.id))
  local oldselect, oldnotify=vim.ui.select,vim.notify
  local prompt
  vim.notify=function() end
  vim.ui.select=function(items,opts,cb) prompt=opts.prompt; cb(items[#items]) end
  cp.remove(other); assert(s:get(p.id) and prompt:find("2 份源码"))
  vim.ui.select=function(items,_,cb) cb(items[1]) end
  cp.remove(other); assert(not s:get(p.id) and not s:binding(otherpath) and not s:binding(source))
  assert(vim.uv.fs_stat(source) and vim.uv.fs_stat(otherpath))
  local guarded = assert(s:save({id="cf-8000-B",name="write failure",tests={}},0))
  local original=h.read(s:problem_path(guarded.id))
  assert(vim.uv.fs_chmod(s.root .. "/problems",320)) -- 0500
  guarded.name="must not be saved"
  local saved, err=s:save(guarded,guarded.revision)
  assert(vim.uv.fs_chmod(s.root .. "/problems",448))
  assert(not saved and err:find("临时文件失败"),err)
  assert(h.read(s:problem_path(guarded.id)) == original)
  local bindingkey="binding-" .. vim.fn.sha256(require("cp_cache.identity").source(otherpath))
  h.write(s.root .. "/locks/" .. bindingkey .. ".lock",vim.json.encode({pid=2147483647}))
  assert(s:unlock(bindingkey))
  vim.notify,vim.ui.select=oldnotify,oldselect
  -- Actual original command fallback remains available to an unmanaged language.
  local py=h.root .. "/fixtures/acceptance/python-" .. vim.uv.hrtime() .. "/main.py"
  h.write(py,"print(1)\n"); vim.cmd.edit(vim.fn.fnameescape(py)); vim.bo.filetype="python"
  vim.cmd("CompetiTest add_testcase")
  vim.api.nvim_buf_set_lines(vim.fn.bufnr("CompetiTestEditInput"),0,-1,false,{"input"})
  vim.api.nvim_buf_set_lines(vim.fn.bufnr("CompetiTestEditOutput"),0,-1,false,{"output"})
  h.map(vim.fn.bufnr("CompetiTestEditInput"),"<C-s>")
  assert(h.read(vim.fs.dirname(py) .. "/testcases/main.0.in") == "input")
  assert(not s:binding(py))
  print("P5 EDGES PASS: WA, compile failure blocks stale binary, timeout/kill/queue/unload cleanup, confirmed shared removal, real I/O failure, binding lock recovery and non-CPP fallback")
end
