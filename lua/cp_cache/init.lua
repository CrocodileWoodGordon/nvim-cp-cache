local M = {}
local api = vim.api
local identity = require("cp_cache.identity")
local Store = require("cp_cache.store")
local adapter = require("cp_cache.adapter")
local state = {}
local subcommands = { "receive", "find", "info", "migrate", "forget", "remove", "reindex", "export", "unlock", "run", "add", "edit", "delete" }

function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "cp-cache" })
end
local function problem_label(p)
  local id = p.id:match("^local%-") and "本地题目" or p.id:match("^url%-") and "网页题目" or p.id
  return id .. " · " .. p.name:gsub("[%c]", " ") .. "（共享样例）"
end
local function failure(err) M.notify(err, vim.log.levels.ERROR); return nil, err end

function M.store()
  if not state.store then return nil, "cp-cache 尚未 setup" end
  return state.store
end
function M.options() return vim.deepcopy(state.opts or {}) end

function M.capture(buf)
  buf = (not buf or buf == 0) and api.nvim_get_current_buf() or buf
  if not api.nvim_buf_is_valid(buf) or not api.nvim_buf_is_loaded(buf) or vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype ~= "cpp" then return nil, "请先打开具名 C++ 源码" end
  local path, err = identity.source(buf); if not path then return nil, err end
  return { buf = buf, path = path }
end

function M.valid_target(target)
  if not api.nvim_buf_is_valid(target.buf) or not api.nvim_buf_is_loaded(target.buf) then return nil, "发起操作的源码 buffer 已关闭；操作取消" end
  local path, err = identity.source(target.buf)
  if path ~= target.path then return nil, err or "源码路径已变化；操作取消，请重新发起" end
  return true
end

function M.get_testcases(buf)
  local target, err = M.capture(buf); if not target then return nil, err end
  local store, why = M.store(); if not store then return nil, why end
  return store:testcases(target.path)
end

local function current(buf, ensure)
  local target, err = M.capture(buf); if not target then return nil, nil, err end
  local store, serr = M.store(); if not store then return nil, nil, serr end
  local p, why = store:for_source(target.path); if why then return nil, nil, why end
  if not p and ensure then
    local id = assert(identity.problem(nil, target.path))
    p, why = store:get(id)
    if why then return nil, nil, why end
    if p then return nil, nil, "源码的手工题目已存在，请用 CPCache find 重新关联" end
    p, why = store:save({ id = id, name = vim.fs.basename(target.path), tests = {} }, 0)
    if not p then return nil, nil, why end
    local bound, berr = store:bind(target.path, id)
    if not bound then return nil, nil, "题目已保存，但关联失败: " .. berr end
    local _, ierr = store:list(); if ierr then return nil, nil, ierr end
  end
  return p, target, not p and "当前源码没有缓存题目；请接收、添加、搜索或迁移样例" or nil
end

function M.bind(target, id, done)
  local ok, err = M.valid_target(target); if not ok then failure(err); if done then done() end; return end
  local store = assert(M.store())
  local p, why = store:get(id); if not p then failure(why or "题目不存在"); if done then done() end; return end
  local previous, berr = store:binding(target.path)
  if berr then failure(berr); if done then done() end; return end
  local function apply(choice)
    if choice ~= "关联" then if done then done() end; return end
    local valid, verr = M.valid_target(target)
    if not valid then failure(verr); if done then done() end; return end
    local bound, binderr = store:bind(target.path, id, previous and previous.problem_id or false)
    if not bound then failure(binderr) else M.notify("已关联 " .. problem_label(p)) end
    if done then done(bound) end
  end
  if previous and previous.problem_id ~= id then
    vim.ui.select({ "关联", "取消" }, { prompt = "当前 " .. previous.problem_id .. " → " .. problem_label(p) .. "；旧题保留" }, apply)
  else apply("关联") end
end

function M.run(buf, opts)
  local target, err = M.capture(buf); if not target then return failure(err) end
  local store, why = M.store(); if not store then return failure(why) end
  local ok, runner, rerr = pcall(adapter.run, target.buf, store, target.path, opts)
  if not ok then return failure(tostring(runner)) end
  if not runner then return failure(rerr) end
  return runner
end

local function editor(buf, number, add)
  local p, target, err = current(buf, add); if not p then return failure(err) end
  local tests = {}; for _, tc in ipairs(p.tests) do tests[tc.id] = tc end
  if add then number = 0; while tests[number] do number = number + 1 end end
  local function open(n)
    local original = tests[n]
    if not original and not add then return failure("不存在的样例: " .. tostring(n)) end
    original = original or { id = n, input = "", output = "", origin = "manual" }
    M.notify("编辑 " .. problem_label(p))
    adapter.editor_widget(target.buf, tostring(n) .. " · " .. problem_label(p), original.input, original.output, function(tc)
      local function save(with_output)
        if with_output == "取消" then return end
        local valid, verr = M.valid_target(target); if not valid then failure(verr); return end
        local changed = vim.deepcopy(p)
        local replacement = { id = n, input = tc.input, output = with_output == "无标准答案" and nil or tc.output, origin = "manual" }
        if with_output == "无标准答案" then replacement.output = nil end
        local found = false
        for i, case in ipairs(changed.tests) do if case.id == n then changed.tests[i], found = replacement, true; break end end
        if not found then changed.tests[#changed.tests + 1] = replacement end
        table.sort(changed.tests, function(a,b) return a.id < b.id end)
        local saved, why = state.store:save(changed, p.revision)
        if not saved then
          failure(why)
          if why:find("冲突") then
            vim.ui.select({ "重新加载", "取消" }, { prompt = "样例已变化，当前编辑未保存" }, function(choice)
              if choice == "重新加载" then vim.schedule(function() if M.valid_target(target) then M.edit(target.buf, n) end end) end
            end)
          end
          return
        end
        p = saved
        local _, ierr = state.store:list(); if ierr then failure("样例已保存，但索引更新失败: " .. ierr); return end
        M.notify("已保存 " .. problem_label(p) .. " / " .. n)
      end
      if tc.output == "" then
        local choices = original.output == nil and { "无标准答案", "期待空输出", "取消" } or { "期待空输出", "无标准答案", "取消" }
        vim.ui.select(choices, { prompt = "空白输出的含义" }, function(choice) if choice then save(choice) end end)
      else save("有标准答案") end
    end)
  end
  if number ~= nil then
    number = tonumber(number); if not number or number < 0 or number % 1 ~= 0 then return failure("样例编号必须是非负整数") end
    return open(number)
  end
  if not next(tests) then return failure("当前题目没有样例") end
  adapter.picker_widget(target.buf, tests, "编辑 " .. problem_label(p), open)
end
function M.add(buf) return editor(buf, nil, true) end
function M.edit(buf, number) return editor(buf, number, false) end

function M.delete(buf, number)
  local p, target, err = current(buf); if not p then return failure(err) end
  local tests = {}; for _, tc in ipairs(p.tests) do tests[tc.id] = tc end
  local function selected(n)
    n = tonumber(n); if not n or not tests[n] then return failure("不存在的样例编号") end
    vim.ui.select({ "删除", "取消" }, { prompt = "删除 " .. problem_label(p) .. " / " .. n }, function(choice)
      if choice ~= "删除" then return end
      local valid, verr = M.valid_target(target); if not valid then failure(verr); return end
      p.tests = vim.tbl_filter(function(tc) return tc.id ~= n end, p.tests)
      local saved, why = state.store:save(p, p.revision)
      if not saved then failure(why); return end
      local _, ierr = state.store:list(); if ierr then failure(ierr); return end
      M.notify("已删除样例 " .. n .. " · " .. problem_label(p))
    end)
  end
  if number ~= nil then return selected(number) end
  if not next(tests) then return failure("当前题目没有样例") end
  adapter.picker_widget(target.buf, tests, "删除 " .. problem_label(p), selected)
end

function M.pick(buf)
  local target, err = M.capture(buf); if not target then return failure(err) end
  require("cp_cache.picker").open(assert(M.store()), function(p) if p then M.bind(target, p.id) end end, M.notify, state.opts.picker == "select")
end

function M.info(buf)
  local p, target, err = current(buf); if not p then return failure(err) end
  local lines = { problem_label(p), "源码: " .. target.path, "缓存: " .. state.store:problem_path(p.id), "样例数: " .. #p.tests }
  M.notify(table.concat(lines, "\n")); return p, target
end
function M.migrate(buf, mode)
  local target, err = M.capture(buf); if not target then return failure(err) end
  local p, why = require("cp_cache.migrate").copy(assert(M.store()), target.buf, target.path, mode)
  if not p then return failure(why) end
  M.notify("迁移并回读校验成功，旧文件保留: " .. problem_label(p)); return p
end
function M.export(buf, mode)
  local target, err = M.capture(buf); if not target then return failure(err) end
  local path, why = require("cp_cache.migrate").export(assert(M.store()), target.path, mode)
  if not path then return failure(why) end
  M.notify("已导出: " .. path); return path
end
function M.forget(buf)
  local target, err = M.capture(buf); if not target then return failure(err) end
  local ok, why = state.store:forget(target.path); if not ok then return failure(why) end
  M.notify("已解除源码关联，题目和样例保留"); return true
end
function M.remove(buf, id)
  local p, _, err
  if id then p, err = state.store:get(id) else p, _, err = current(buf) end
  if not p then return failure(err or "题目不存在") end
  local bindings, why = state.store:bindings(p.id); if not bindings then return failure(why) end
  vim.ui.select({ "删除题目及全部样例", "取消" }, { prompt = problem_label(p) .. "，关联 " .. #bindings .. " 份源码；手工样例也会删除" }, function(choice)
    if choice ~= "删除题目及全部样例" then return end
    local ok, rerr = state.store:remove(p.id, p.revision); if not ok then failure(rerr); return end
    local _, ierr = state.store:list(); if ierr then failure(ierr); return end
    M.notify("题目已删除；导出快照保留")
  end)
end

function M.receive(mode, buf) return require("cp_cache.receiver").start(mode, buf, M) end
function M.stop_receive() return require("cp_cache.receiver").stop() end
function M.receive_status() return require("cp_cache.receiver").status() end

function M.dispatch(args, buf)
  local sub = args[1]
  if sub == "receive" and (args[2] == "status" or args[2] == "stop") then
    if #args ~= 2 then failure("receive 需要一个参数"); return true end
    if args[2] == "stop" then M.stop_receive() else M.notify(M.receive_status()) end
    return true
  end
  if vim.bo[buf].filetype ~= "cpp" then return false end
  local target, source_error = M.capture(buf)
  if not target then failure(source_error); return true end
  local counts = { add_testcase={1,1}, edit_testcase={1,2}, delete_testcase={1,2}, show_ui={1,1}, receive={2,2}, convert={2,2} }
  local count = counts[sub]
  if count and (#args < count[1] or #args > count[2]) then failure("CompetiTest " .. sub .. " 参数数量错误"); return true end
  if sub == "run" or sub == "run_no_compile" then M.run(buf, { compile = sub == "run", numbers = #args > 1 and {unpack(args, 2)} or nil })
  elseif sub == "show_ui" then M.run(buf, { only_show = true })
  elseif sub == "add_testcase" then M.add(buf)
  elseif sub == "edit_testcase" then M.edit(buf, args[2])
  elseif sub == "delete_testcase" then M.delete(buf, args[2])
  elseif sub == "receive" then M.receive(args[2], buf)
  elseif sub == "convert" then
    local modes = { files_to_singlefile = "msgpack", singlefile_to_files = "files", auto = "auto" }
    if not modes[args[2]] then failure("convert 参数应为 auto/files_to_singlefile/singlefile_to_files") else M.export(buf, modes[args[2]]) end
  else failure("未知 CompetiTest 子命令: " .. tostring(sub)) end
  return true
end

local function complete(lead, line)
  local words = vim.split(line:sub(1, #line - #lead), "%s+", { trimempty = true })
  local choices = subcommands
  if #words >= 2 then choices = words[2] == "receive" and { "testcases", "problem", "contest", "persistently", "status", "stop" }
    or (words[2] == "export" or words[2] == "migrate") and { "files", "msgpack" } or {} end
  return vim.tbl_filter(function(s) return s:sub(1, #lead) == lead end, choices)
end

function M.command(args)
  local sub, arg, buf = args[1], args[2], api.nvim_get_current_buf()
  if #args > 2 then return failure("CPCache 子命令最多接受一个参数") end
  if arg and ({find=true,info=true,forget=true,reindex=true,run=true,add=true})[sub] then return failure("CPCache " .. sub .. " 不接受参数") end
  if sub == "receive" then
    if arg == "stop" then M.stop_receive() elseif arg == "status" then M.notify(M.receive_status()) else return M.receive(arg or "testcases", buf) end
  elseif sub == "find" then return M.pick(buf)
  elseif sub == "info" then return M.info(buf)
  elseif sub == "migrate" then return M.migrate(buf, arg)
  elseif sub == "forget" then return M.forget(buf)
  elseif sub == "remove" then return M.remove(buf, arg)
  elseif sub == "reindex" then local list, err, errors = state.store:list(); if not list then return failure(err) end; for _, why in ipairs(errors) do M.notify(why, vim.log.levels.WARN) end; M.notify("索引已重建: " .. #list .. " 题")
  elseif sub == "export" then return M.export(buf, arg or "files")
  elseif sub == "unlock" then
    if arg == "binding" then
      local target, err = M.capture(buf); if not target then return failure(err) end
      arg = "binding-" .. vim.fn.sha256(target.path)
    end
    local ok, err = state.store:unlock(arg); if not ok then return failure(err) end; M.notify("已恢复死进程的锁")
  elseif sub == "run" then return M.run(buf)
  elseif sub == "add" then return M.add(buf)
  elseif sub == "edit" then return M.edit(buf, arg)
  elseif sub == "delete" then return M.delete(buf, arg)
  else return failure("CPCache 子命令: " .. table.concat(subcommands, ", ")) end
end

function M.setup(opts)
  local options = vim.tbl_deep_extend("force", { cache_root = vim.fn.stdpath("config") .. "/.cache/cp-cache/v1", port = 27121 }, state.opts or {}, opts or {})
  if state.store and state.store.root ~= options.cache_root and package.loaded["cp_cache.receiver"] then M.stop_receive() end
  local store, err = Store.new(options.cache_root); if not store then return failure(err) end
  state.opts, state.store = options, store
  local installed, why = pcall(adapter.install_dispatch, M.dispatch)
  if not installed then return failure(tostring(why)) end
  api.nvim_create_user_command("CPCache", function(args) M.command(args.fargs) end, { nargs = "+", bar = true, force = true, complete = complete })
  local group = api.nvim_create_augroup("CPCache", { clear = true })
  api.nvim_create_autocmd({"BufUnload", "BufFilePost"}, { group = group, callback = function(ev)
    adapter.on_unload(ev.buf)
  end })
  api.nvim_create_autocmd("VimLeavePre", { group = group, callback = function()
    if package.loaded["cp_cache.receiver"] then M.stop_receive() end
    local buffers = vim.tbl_keys(adapter.runners()); for _, buf in ipairs(buffers) do adapter.cleanup(buf) end
  end })
  return M
end
return M
