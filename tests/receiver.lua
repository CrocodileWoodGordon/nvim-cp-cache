return function(h)
  local cp, receiver, a = require("cp_cache"), require("cp_cache.receiver"), require("cp_cache.adapter")
  local root = h.root .. "/store/http-" .. vim.uv.hrtime()
  assert(cp.setup({cache_root=root, port=0, batch_timeout_ms=120, idle_timeout_ms=120}))
  local s = assert(cp.store())
  local oldnotify, oldselect, oldinput = vim.notify, vim.ui.select, vim.ui.input
  local messages = {}
  vim.notify = function(message) messages[#messages + 1] = message end
  vim.ui.select = function(items, _, callback) callback(items[1]) end
  local buf, path = h.source("receiver/current/main.cpp")
  local before = h.snapshot(vim.fs.dirname(path))
  local function task(number, batch, size, input)
    return {name=number .. ". 中文题", group="Codeforces - Test Round", url="https://codeforces.com/contest/1234/problem/" .. number,
      timeLimit=1000, memoryLimit=256, interactive=false, input={type="stdin"}, output={type="stdout"},
      tests={{input=input or "中文\r\n\n",output=""},{input=""}}, batch={id=batch, size=size or 1}}
  end
  local function start(mode, target)
    assert(cp.receive(mode, target or buf))
    local _, status = receiver.status(); assert(status.active and status.port > 0); return status.port
  end
  local function request(port, spec)
    local result
    vim.system({"python3",vim.env.CP_CACHE_PLUGIN .. "/tests/http_client.py",tostring(port)}, {stdin=vim.json.encode(spec),text=true}, vim.schedule_wrap(function(r) result=r end))
    h.await(function() return result ~= nil end,"HTTP client timed out",10000)
    assert(result.code == 0, result.stderr)
    return vim.json.decode(result.stdout)
  end
  local function post(port, value, fragments) return request(port,{body=vim.json.encode(value),fragments=fragments}) end
  local port = start("testcases")
  local other, otherpath = h.source("receiver/other/main.cpp")
  local first = post(port,task("A","one"),true)
  assert(first.code == 202, vim.inspect(first) .. vim.inspect(messages))
  h.await(function() return s:binding(path) ~= nil end)
  assert(not s:binding(otherpath))
  assert(cp.get_testcases(buf)[0].input == "中文\r\n\n" and cp.get_testcases(buf)[0].output == "" and cp.get_testcases(buf)[1].output == nil)
  assert(not select(2,receiver.status()).active)
  vim.api.nvim_set_current_buf(buf)
  port = start("testcases"); vim.ui.select = function(items,_,callback) callback(items[#items]) end
  assert(post(port,task("B","cancel")).code == 202); vim.wait(20)
  assert(s:binding(path).problem_id == "cf-1234-A" and not s:get("cf-1234-B"))
  vim.ui.select = function(items,_,callback) callback(items[1]) end
  port = start("testcases"); assert(post(port,task("B","switch")).code == 202); vim.wait(20)
  assert(s:binding(path).problem_id == "cf-1234-B" and s:get("cf-1234-A"))
  local p = assert(s:get("cf-1234-B")); p.tests[#p.tests+1]={id=8,input="hand",origin="manual"}; assert(s:save(p,p.revision))
  port = start("testcases"); assert(post(port,task("B","replace",1,"new\n")).code == 202); vim.wait(20)
  p = assert(s:get("cf-1234-B")); assert(#p.tests == 3 and p.tests[3].id == 8)
  local revision = p.revision
  port = start("testcases"); assert(post(port,task("B","duplicate",1,"new\n")).code == 202); vim.wait(20)
  assert(s:get("cf-1234-B").revision == revision)
  port = start("persistently")
  assert(request(port,{method="OPTIONS",headers=""}).code == 204)
  assert(request(port,{body="{broken"}).code == 400)
  assert(request(port,{body='{"name":"bad"}'}).code == 400)
  assert(request(port,{method="GET",headers=""}).code == 405)
  assert(request(port,{body="{}",headers="Content-Length: 2\r\nContent-Length: 2\r\n"}).code == 400)
  assert(request(port,{body="{}",headers="Content-Length: 9000000\r\n"}).code == 413)
  assert(request(port,{body="{}",headers="Content-Length: 2\r\nX-Large: " .. string.rep("x",17000) .. "\r\n"}).code == 431)
  assert(request(port,{body="{}",idle=true}).code == 408)
  local occupied = vim.uv.new_tcp(); occupied:bind("127.0.0.1",port)
  assert(not occupied:listen(1,function() end)); occupied:close()
  assert(not cp.receive("persistently",buf))
  assert(cp.stop_receive()); assert(cp.stop_receive())
  occupied = vim.uv.new_tcp(); assert(occupied:bind("127.0.0.1",0)); assert(occupied:listen(1,function() end))
  assert(cp.setup({port=occupied:getsockname().port})); assert(not cp.receive("testcases",buf))
  occupied:close(); assert(cp.setup({port=0}))
  vim.wait(20); port = start("testcases", other)
  vim.api.nvim_set_current_buf(other); vim.api.nvim_buf_delete(other,{force=true}); vim.wait(20)
  assert(post(port,task("C","closed")).code == 202); vim.wait(20)
  assert(not s:binding(otherpath)); assert(table.concat(messages,"\n"):find("已关闭"))
  assert(vim.deep_equal(before,h.snapshot(vim.fs.dirname(path))),"testcases receive polluted source directory")
  local create = h.root .. "/fixtures/receiver/created-" .. vim.uv.hrtime()
  local template = h.root .. "/fixtures/receiver/template.cpp"
  h.write(template,"// $(PROBLEM)\nint main(){}\n")
  local cfg = {template_file={cpp=template},evaluate_template_modifiers=false, received_files_extension="cpp",open_received_problems=false,open_received_contests=false,
    received_problems_path=function(t,e) return create .. "/single." .. e end,
    received_problems_prompt_path=true, received_contests_directory=create .. "/$(CONTEST)",
    received_contests_prompt_directory=true, received_contests_prompt_extension=true,
    received_contests_problems_path=function(t,e) return t._id .. "." .. e end}
  a.setup_dependency(cfg)
  vim.ui.input = function(opts,cb) cb(opts.default) end
  port = start("problem",buf)
  assert(post(port,task("D","new-problem")).code == 202); vim.wait(20)
  assert(h.read(create .. "/single.cpp") == "// $(PROBLEM)\nint main(){}\n")
  assert(s:for_source(create .. "/single.cpp").id == "cf-1234-D")
  port = start("problem",buf)
  assert(post(port,task("D","existing")).code == 202); vim.wait(20)
  assert(h.read(create .. "/single.cpp") == "// $(PROBLEM)\nint main(){}\n")
  a.setup_dependency({evaluate_template_modifiers=true})
  port = start("contest",buf)
  local directone,directtwo=task("J","direct-contest",2),task("K","direct-contest",2)
  directone.group,directtwo.group="Codeforces - Direct Round","Codeforces - Direct Round"
  assert(post(port,directone).code==202 and post(port,directtwo).code==202); vim.wait(20)
  assert(s:for_source(create .. "/Direct Round/cf-1234-K.cpp").id=="cf-1234-K")
  port = start("persistently",buf)
  local one, two = task("E","round-one",2),task("F","round-one",2)
  one.group, two.group = "Codeforces - Round One", "Codeforces - Round One"
  local three, four = task("G","round-two",2),task("H","round-two",2)
  three.group, four.group = "Codeforces - Round Two", "Codeforces - Round Two"
  assert(post(port,one).code == 202); assert(post(port,one).code == 202)
  assert(post(port,three).code == 202); assert(post(port,two).code == 202); assert(post(port,four).code == 202)
  vim.wait(40)
  assert(s:for_source(create .. "/Round One/cf-1234-E.cpp").id == "cf-1234-E")
  assert(s:for_source(create .. "/Round Two/cf-1234-H.cpp").id == "cf-1234-H")
  assert(h.read(create .. "/Round One/cf-1234-E.cpp") == "// E. 中文题\nint main(){}\n")
  assert(post(port,task("I","incomplete",2)).code == 202)
  vim.wait(180); assert(table.concat(messages,"\n"):find("批次超时"))
  assert(post(port,task("I","incomplete",1)).code == 202); vim.wait(20)
  assert(s:binding(path).problem_id == "cf-1234-I")
  vim.ui.select=function(items,_,callback)
    if items[1]=="仅样例（发起接收的源码）" then callback(items[2]) else callback(items[1]) end
  end
  vim.ui.input=function(_,cb) cb(create .. "/persistent.cpp") end
  assert(post(port,task("Y","persistent-full")).code==202); vim.wait(20)
  assert(s:for_source(create .. "/persistent.cpp").id=="cf-1234-Y")
  cp.stop_receive()
  local snap = h.snapshot(create)
  for name in pairs(snap) do assert(name:match("/+$") or name:match("%.cpp$"),"receiver created non-source: " .. name) end
  -- A pending user choice must become inert after stop.
  local pending
  vim.ui.input = function(_,cb) pending=cb end
  port = start("problem",buf); assert(post(port,task("Z","pending")).code == 202); vim.wait(20); assert(pending)
  cp.stop_receive(); pending(create .. "/should-not-exist.cpp"); assert(not vim.uv.fs_stat(create .. "/should-not-exist.cpp"))
  vim.notify,vim.ui.select,vim.ui.input = oldnotify,oldselect,oldinput
  print("P3 PASS: actual fragmented HTTP, CORS/errors/limits/timeouts, captured buffer, duplicate/rebind/manual preservation, templates, interleaved contests, stop/cancel and source snapshots")
end
