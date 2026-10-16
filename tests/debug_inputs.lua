-- Capture launch parameters only. Real debugger execution is tested separately.
return function(h, buf, source)
  require("lazy").load({plugins={"nvim-dap"}})
  local cp, cache, dap = require("cp"), require("cp_cache"), require("dap")
  local original_run, oldselect, oldinput = dap.run, vim.ui.select, vim.ui.input
  local launches = {}
  dap.run = function(config) launches[#launches+1]=config end
  local function launch(number)
    local previous = #launches
    local win = vim.fn.bufwinid(buf)
    if win > 0 then vim.api.nvim_set_current_win(win) end
    vim.api.nvim_set_current_buf(buf)
    cp.debug(number)
    h.await(function() return #launches > previous end,"debug build/launch callback missing",30000)
    local config = launches[#launches]
    assert(config.type == "gdb" and config.cwd == vim.fs.dirname(source) and vim.fn.executable(config.program) == 1)
    return config
  end
  local first = launch("0")
  assert(h.read(first.cp_input) == "5\n1 2 3 4 5\n")
  local s = assert(cache.store())
  local p = assert(s:for_source(source)); p.tests[1].input = "new\r\n\n"; assert(s:save(p,p.revision))
  local next_launch = launch("0")
  assert(h.read(next_launch.cp_input) == "new\r\n\n" and h.read(first.cp_input) == "5\n1 2 3 4 5\n")
  local second = launch("2"); assert(h.read(second.cp_input) == "3\n1 2 3\n")
  local inputpath = h.root .. "/fixtures/full/input 中文 'quote'.in"
  h.write(inputpath,"file\r\n\n")
  vim.ui.select = function(items,_,callback) for _, item in ipairs(items) do if item.file then callback(item); return end end end
  vim.ui.input = function(_,callback) callback(inputpath) end
  assert(launch().cp_input == inputpath)
  vim.ui.select = function(items,_,callback) for _, item in ipairs(items) do if item.interactive then callback(item); return end end end
  local interactive = launch(); assert(interactive.cp_tty and interactive.cp_terminal_job and not interactive.cp_input)
  assert(vim.fn.jobstop(interactive.cp_terminal_job) == 1)
  vim.ui.select = function(items,_,callback) for _, item in ipairs(items) do if item.input == "" and item.number == nil then callback(item); return end end end
  assert(h.read(launch().cp_input) == "")
  local path = assert(s:problem_path(p.id)); local original = h.read(path)
  h.write(path,"{corrupt")
  local calls = #launches
  cp.debug("0"); vim.wait(30); assert(#launches == calls,"corrupt cache incorrectly launched debugger")
  assert(vim.v.errmsg:find("JSON 损坏"),"missing cache error diagnostic")
  vim.v.errmsg = ""
  h.write(path,original)
  dap.run, vim.ui.select, vim.ui.input = original_run, oldselect, oldinput
  print("A17 PASS (launch capture): samples 0/2, edited bytes, immutable snapshots, file/PTY/EOF and corrupt-cache abort")
end
