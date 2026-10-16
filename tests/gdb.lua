return function(h, buf, source)
  require("lazy").load({plugins={"nvim-dap"}})
  local dap, cp = require("dap"), require("cp")
  local stops, output = 0, {}
  dap.listeners.after.event_stopped.cp_cache_verify = function() stops=stops+1 end
  dap.listeners.after.event_output.cp_cache_verify = function(_,event) output[#output+1]=event.output end
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_win_set_cursor(0,{8,0})
  dap.set_breakpoint()
  cp.debug("0")
  local function stopped(previous)
    h.await(function() return stops > previous and dap.session() and dap.session().stopped_thread_id ~= nil end,"real GDB did not stop: " .. table.concat(output,""),30000)
  end
  local function request(command,args)
    local finished, result, failure
    dap.session():request(command,args,function(err,body) failure,result,finished=err,body,true end)
    h.await(function() return finished end,"DAP response missing: " .. command)
    assert(not failure,vim.inspect(failure)); return result
  end
  stopped(0)
  local entry = request("stackTrace",{threadId=dap.session().stopped_thread_id})
  assert(entry.stackFrames[1].name:find("main"))
  local previous=stops; dap.continue(); stopped(previous)
  local stack = request("stackTrace",{threadId=dap.session().stopped_thread_id})
  assert(#stack.stackFrames >= 6 and stack.stackFrames[1].name:find("sum_from"),vim.inspect(stack))
  local frame = stack.stackFrames[1]
  local scopes = request("scopes",{frameId=frame.id})
  local locals={}
  for _, scope in ipairs(scopes.scopes) do
    if scope.name:lower():find("local") then
      for _, variable in ipairs(request("variables",{variablesReference=scope.variablesReference}).variables) do locals[variable.name]=variable.value end
    end
  end
  assert(locals.current == "5" and locals.rest == "0",vim.inspect(locals))
  local evaluation = request("evaluate",{frameId=frame.id,expression="current + rest",context="watch"})
  assert(evaluation.result == "5",vim.inspect(evaluation))
  previous=stops; dap.step_over(); stopped(previous)
  local after = request("stackTrace",{threadId=dap.session().stopped_thread_id})
  assert(after.stackFrames[1].line ~= frame.line or after.stackFrames[1].id ~= frame.id)
  h.write(h.root .. "/reports/gdb-evidence.json",vim.json.encode({status="PASS",frames=#stack.stackFrames,locals=locals,evaluation=evaluation.result,stops=stops,source=source}))
  dap.terminate()
  h.await(function() return dap.session() == nil end,"GDB termination did not finish")
  require("dapui").close()
  print("A18 PASS (real GDB): cached sample 0, main stop, recursive breakpoint, stack, locals, watch evaluation and single step")
end
