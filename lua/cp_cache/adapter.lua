-- CompetiTest exports are version-sensitive. Keep every dependency call here.
local M = {}
local api = vim.api
local editor_source
local function fit_title(text, width)
  text = tostring(text):gsub("[%c]", " ")
  local count = vim.fn.strchars(text)
  while count > 0 and vim.fn.strdisplaywidth(text) > math.max(4, width) do
    count = count - 1; text = vim.fn.strcharpart(text, 0, count)
  end
  return text
end
local function dependency(name)
  local ok, value = pcall(require, "competitest" .. (name and "." .. name or ""))
  if not ok then error("cp-cache: CompetiTest dependency unavailable: " .. tostring(value)) end
  return value
end

function M.setup_dependency(opts)
  dependency().setup(opts)
end

function M.config(buf)
  dependency("config").load_buffer_config(buf)
  return dependency("config").get_buffer_config(buf)
end

function M.receiver_config(directory)
  return dependency("config").load_local_config_and_extend(directory or vim.fn.getcwd())
end

function M.runners()
  return dependency("commands").runners
end

function M.new_runner(buf)
  M.config(buf)
  local runner = dependency("runner"):new(buf)
  if not runner then error("cp-cache: unable to construct CompetiTest runner") end
  M.runners()[buf] = runner
  return runner
end

function M.cleanup(buf)
  if editor_source == buf then
    editor_source = nil
    for _, win in ipairs(api.nvim_list_wins()) do
      if api.nvim_win_is_valid(win) then
        local name = api.nvim_buf_get_name(api.nvim_win_get_buf(win))
        if name:match("CompetiTestEditInput$") or name:match("CompetiTestEditOutput$") then pcall(api.nvim_win_close, win, true) end
      end
    end
  end
  local runner = M.runners()[buf]
  if not runner then return end
  runner._cp_dead = true
  -- Upstream kill_all_processes alone starts queued tests from exit callbacks.
  runner.next_tc = math.huge
  runner:kill_all_processes()
  if runner.ui then runner.ui:delete() end
  M.runners()[buf] = nil
end

function M.eval_file(path, format)
  return dependency("utils").eval_string(path, format)
end

function M.run(buf, store, source, opts)
  opts = opts or {}
  if opts.only_show then
    local r = M.runners()[buf]
    if not r then return nil, "尚无运行结果" end
    r:set_restore_winid(api.nvim_get_current_win()); r:show_ui(); return r
  end
  local tests, err = store:testcases(source)
  if not tests then return nil, err end
  if opts.numbers then
    local selected = {}
    for _, number in ipairs(opts.numbers) do
      number = tonumber(number)
      if not number or not tests[number] then return nil, "不存在的样例编号: " .. tostring(number) end
      selected[number] = tests[number]
    end
    tests = selected
  end
  if not next(tests) then return nil, "当前题目没有样例；请接收、添加或迁移样例" end
  M.cleanup(buf)
  local r = M.new_runner(buf)
  local native_run, native_single, native_kill = r.run_testcases, r.run_testcase, r.kill_all_processes
  r.kill_all_processes = function(self)
    self.next_tc = math.huge
    return native_kill(self)
  end
  r.run_testcases = function(self, data, compile)
    if self._cp_dead then return end
    if data == nil then
      -- A native UI rerun must resolve the current binding and current store data.
      local result, why = M.run(buf, store, source, { compile = self.compile })
      if not result then vim.notify(why, vim.log.levels.ERROR, { title = "cp-cache" }) end
      return
    end
    return native_run(self, data, compile)
  end
  r.run_testcase = function(self, index)
    if self._cp_dead then return end
    local tc = self.tcdata[index]
    if not tc then return end
    if tc.running then vim.defer_fn(function() if not self._cp_dead then self:run_testcase(index) end end, 20); return end
    if tc.tcnum ~= "Compile" then
      local fresh, why = store:testcases(source)
      if not fresh or not fresh[tc.tcnum] then
        vim.notify(why or "该样例已被删除，请重新运行全部样例", vim.log.levels.ERROR, { title = "cp-cache" }); return
      end
      local case = fresh[tc.tcnum]
      tc.stdin = vim.split(case.input, "\n", { plain = true })
      tc.expout = case.output ~= nil and vim.split(case.output, "\n", { plain = true }) or nil
    end
    return native_single(self, index)
  end
  r:set_restore_winid(api.nvim_get_current_win())
  r:run_testcases(tests, opts.compile ~= false)
  r:show_ui()
  return r
end

function M.editor_widget(buf, number, input, output, callback, win)
  local cfg = M.config(buf)
  number = number ~= nil and fit_title(number, math.floor(vim.o.columns * cfg.editor_ui.popup_width) - 12) or nil
  editor_source = buf
  dependency("widgets").editor(buf, number, input, output, callback, win or api.nvim_get_current_win())
end

function M.picker_widget(buf, tests, title, callback, win)
  local cfg = M.config(buf)
  title = fit_title(title, math.floor(vim.o.columns * cfg.picker_ui.width) - 4)
  dependency("widgets").picker(buf, tests, title, callback, win or api.nvim_get_current_win())
end

function M.resize()
  dependency().resize_ui()
end

local commands = { "add_testcase", "edit_testcase", "delete_testcase", "convert", "run", "run_no_compile", "show_ui", "receive" }
function M.complete(lead, line)
  local words = vim.split(line:sub(1, #line - #lead), "%s+", { trimempty = true })
  local choices = commands
  if #words >= 2 then
    choices = words[2] == "receive" and { "testcases", "problem", "contest", "persistently", "status", "stop" }
      or words[2] == "convert" and { "auto", "files_to_singlefile", "singlefile_to_files" } or {}
  end
  return vim.tbl_filter(function(s) return s:sub(1, #lead) == lead end, choices)
end

function M.install_dispatch(handler)
  local original = dependency("commands").command
  api.nvim_create_user_command("CompetiTest", function(args)
    if not handler(args.fargs, api.nvim_get_current_buf()) then original(args.args) end
  end, { nargs = "*", bar = true, force = true, complete = M.complete })
end

return M
