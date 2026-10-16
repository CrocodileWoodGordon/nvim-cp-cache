local M = {}
local uv = vim.uv or vim.loop
local identity = require("cp_cache.identity")
local adapter = require("cp_cache.adapter")
local reader = require("cp_cache.migrate").read
local session
local function close(handle)
  if handle and not handle:is_closing() then handle:close() end
end
local function alive(s) return session == s and s.active end
local function report(s, err) s.core.notify(err, vim.log.levels.ERROR) end
local function finish(s)
  if not alive(s) then return end
  s.busy = false
  if s.mode ~= "persistently" then M.stop(true) else vim.schedule(function() M.process(s) end) end
end

function M.validate(task)
  if type(task) ~= "table" or type(task.name) ~= "string" or #task.name > 4096 or
    (task.group ~= nil and type(task.group) ~= "string") then return nil, "无效题目 name/group" end
  local id, canonical = identity.url(task.url)
  if not id then return nil, canonical end
  if type(task.tests) ~= "table" or not vim.islist(task.tests) or #task.tests > 10000 then return nil, "tests 必须是样例数组（最多 10000）" end
  for _, tc in ipairs(task.tests) do
    if type(tc) ~= "table" or type(tc.input) ~= "string" or (tc.output ~= nil and type(tc.output) ~= "string") then return nil, "样例 input/output 必须是字符串，output 可缺省" end
  end
  if task.batch ~= nil then
    if type(task.batch) ~= "table" or type(task.batch.id) ~= "string" or #task.batch.id < 1 or #task.batch.id > 256
      or task.batch.id:find("%c") or type(task.batch.size) ~= "number" or task.batch.size < 1 or task.batch.size > 256 or task.batch.size % 1 ~= 0 then return nil, "无效 batch.id/size（最多 256 题）" end
  end
  for _, field in ipairs({"timeLimit", "memoryLimit"}) do
    if task[field] ~= nil and (type(task[field]) ~= "number" or task[field] < 0) then return nil, "无效 " .. field end
  end
  if task.interactive ~= nil and type(task.interactive) ~= "boolean" then return nil, "无效 interactive" end
  for _, field in ipairs({"input", "output"}) do
    if task[field] ~= nil and (type(task[field]) ~= "table" or type(task[field].type) ~= "string"
      or (task[field].fileName ~= nil and type(task[field].fileName) ~= "string")) then return nil, "无效输入输出描述" end
  end
  if task.languages ~= nil then
    if type(task.languages) ~= "table" or (task.languages.java ~= nil and type(task.languages.java) ~= "table") then return nil, "无效 languages" end
    for _, field in ipairs({"mainClass", "taskClass"}) do
      if task.languages.java and task.languages.java[field] ~= nil and type(task.languages.java[field]) ~= "string" then return nil, "无效 Java 模板字段" end
    end
  end
  task = vim.deepcopy(task)
  task.group = task.group or ""
  task._id, task._canonical = id, canonical
  task.batch = task.batch or { id = "single-" .. id .. "-" .. vim.fn.sha256(vim.json.encode(task.tests)), size = 1 }
  return task
end

-- The task is data only. Modifiers use plain substitution, never Lua or a shell.
function M.format(text, task, extension, sanitize, cwd, date_format)
  if type(text) ~= "string" then return nil, "模板/路径必须是字符串" end
  local judge, contest = task.group:match("^(.-) %- (.*)$")
  local java = task.languages and task.languages.java or {}
  local values = { [""] = "$", HOME = uv.os_homedir(), CWD = cwd, FEXT = extension,
    PROBLEM = task.name, GROUP = task.group, JUDGE = judge or task.group, CONTEST = contest or "unknown_contest",
    URL = task.url, MEMLIM = tostring(task.memoryLimit or ""), TIMELIM = tostring(task.timeLimit or ""),
    JAVA_MAIN_CLASS = java.mainClass or "Main", JAVA_TASK_CLASS = java.taskClass or "Main",
    DATE = os.date(date_format) }
  if sanitize then
    for key, value in pairs(values) do
      if key ~= "HOME" and key ~= "CWD" then
        value = value:gsub('[<>:"/\\|?*%c]', "_")
        if value == "." or value == ".." then value = "_" end
        values[key] = value
      end
    end
  end
  local err
  local result = text:gsub("%$%((.-)%)", function(key)
    if values[key] == nil then err = "未知路径/模板 modifier: $(" .. key .. ")"; return "" end
    return values[key]
  end)
  if err then return nil, err end
  return result
end

local function eval_path(rule, task, extension, s)
  local ok, value, err
  if type(rule) == "function" then ok, value = pcall(rule, task, extension)
  else ok = true; value, err = M.format(rule, task, extension, true, s.cwd, s.cfg.date_format) end
  if not ok then return nil, "路径函数失败: " .. tostring(value) end
  if type(value) ~= "string" or value == "" or value:find("%z") then return nil, err or "无效接收路径" end
  return value
end

local function reindex(s)
  local _, err = s.store:list()
  if err then report(s, "题目已保存，但索引更新失败: " .. err) end
end

local function same_test(a, b) return a.input == b.input and a.output == b.output end
local function fingerprint(task)
  local parts = { task._id, task.name, task.group }
  for _, tc in ipairs(task.tests) do
    parts[#parts + 1] = #tc.input .. ":" .. tc.input
    parts[#parts + 1] = tc.output == nil and "nil" or (#tc.output .. ":" .. tc.output)
  end
  return vim.fn.sha256(table.concat(parts, "\000"))
end

local function import(s, task, source, valid, done)
  if not alive(s) then return end
  local previous, berr = s.store:binding(source)
  if berr then report(s, berr); done(); return end
  local function proceed(choice)
    if not alive(s) then return end
    if choice == "取消" then done(); return end
    local p, err = s.store:get(task._id)
    if err then report(s, err); done(); return end
    local revision, fp = p and p.revision or 0, fingerprint(task)
    local function commit(strategy)
      if not alive(s) then return end
      if not strategy or strategy == "取消" then done(); return end
      local ok, why = valid(); if not ok then report(s, why); done(); return end
      local unchanged = p and p.received_fingerprint == fp
      if not unchanged then
        p = vim.deepcopy(p or { id = task._id, tests = {} })
        if strategy == "替换已接收样例（保留手工）" then p.tests = vim.tbl_filter(function(tc) return tc.origin ~= "received" end, p.tests) end
        local used = {}; for _, tc in ipairs(p.tests) do used[tc.id] = true end
        for _, tc in ipairs(task.tests) do
          local duplicate = false; for _, existing in ipairs(p.tests) do if same_test(tc, existing) then duplicate = true; break end end
          if not duplicate then
            local number = 0; while used[number] do number = number + 1 end
            p.tests[#p.tests + 1] = {id=number, input=tc.input, output=tc.output, origin="received"}; used[number] = true
          end
        end
        table.sort(p.tests, function(a,b) return a.id < b.id end)
        p.name, p.group, p.url, p.canonical_url = task.name, task.group, task.url, task._canonical
        p.metadata = {}; for _, key in ipairs({"timeLimit","memoryLimit","interactive","input","output","languages"}) do p.metadata[key] = task[key] end
        p.received_fingerprint = fp
        local saved, serr = s.store:save(p, revision)
        if not saved then report(s, serr); done(); return end
        p = saved
      end
      local now, nerr = s.store:binding(source)
      if nerr or (now and now.problem_id or false) ~= (previous and previous.problem_id or false) then report(s, nerr or "题目已保存，但源码关联在等待时变化，请搜索重新关联"); done(); return end
      local bound, binderr = s.store:bind(source, task._id, previous and previous.problem_id or false)
      if not bound then report(s, "题目已保存，但关联失败: " .. binderr); done(); return end
      reindex(s)
      s.core.notify((unchanged and "重复样例已复用: " or "已保存: ") .. task._id .. " · " .. task.name)
      if task.interactive then s.core.notify("此题声明为交互题；普通批量样例运行不能模拟交互协议", vim.log.levels.WARN) end
      done(p)
    end
    if p and p.received_fingerprint == fp then commit("追加")
    elseif p and #p.tests > 0 then vim.ui.select({ "替换已接收样例（保留手工）", "追加", "取消" }, {prompt="导入 " .. task._id .. " · " .. task.name .. "（共享样例）"}, commit)
    else commit("追加") end
  end
  if previous and previous.problem_id ~= task._id then
    vim.ui.select({ "切换关联", "取消" }, {prompt="当前 " .. previous.problem_id .. " → " .. task._id .. " · " .. task.name .. "；旧题保留"}, proceed)
  else proceed("继续") end
end

local function source_template(s, task, path)
  local cfg, template = adapter.receiver_config(vim.fs.dirname(path))
  local extension = vim.fn.fnamemodify(path, ":e")
  if type(cfg.template_file) == "table" then template = cfg.template_file[extension]
  elseif type(cfg.template_file) == "string" then template = adapter.eval_file(path, cfg.template_file) end
  if not template then return "" end
  template = template:gsub("^~", uv.os_homedir())
  local bytes, err = reader(template)
  if not bytes then return nil, err or "模板不存在: " .. template end
  if cfg.evaluate_template_modifiers then return M.format(bytes, task, extension, false, s.cwd, cfg.date_format) end
  return bytes
end

local function open_source(s, path, enabled)
  if not enabled or not alive(s) then return end
  local ok, err = pcall(function()
    if vim.bo.modified then vim.cmd.split(vim.fn.fnameescape(path)) else vim.cmd.edit(vim.fn.fnameescape(path)) end
    vim.bo.filetype = "cpp"
  end)
  if not ok then report(s, "题目已保存；打开源码失败: " .. tostring(err)) end
end

local function create_source(s, task, path, open, done)
  if not alive(s) then return end
  if path:sub(1,1) ~= "/" then path = s.cwd .. "/" .. path end
  local canonical, err = identity.source(path)
  if not canonical then report(s, err); done(); return end
  path = canonical
  local function accept(choice)
    if not alive(s) then return end
    if not choice or choice == "取消" then done(); return end
    if choice == "另选路径" then
      vim.ui.input({prompt="新源码路径: ", default=path, completion="file"}, function(nextpath)
        if not alive(s) then return end
        if not nextpath or nextpath == "" then done() else create_source(s, task, nextpath, open, done) end
      end); return
    end
    if choice == "创建" then
      local bytes, why = source_template(s, task, path)
      if not bytes then report(s, why); done(); return end
      local ok, merr = pcall(vim.fn.mkdir, vim.fs.dirname(path), "p")
      if not ok then report(s, "创建源码目录失败: " .. tostring(merr)); done(); return end
      local fd, ferr = uv.fs_open(path, "wx", 420)
      if not fd then report(s, "创建源码失败（可能已被其他程序创建）: " .. tostring(ferr)); done(); return end
      local wrote, werr = uv.fs_write(fd, bytes, 0)
      local closed, cerr = uv.fs_close(fd)
      if wrote ~= #bytes or not closed then report(s, "源码写入失败: " .. tostring(werr or cerr)); done(); return end
    end
    import(s, task, path, function() return alive(s), "接收已停止" end, function(p)
      if p then open_source(s, path, open) end
      done(p)
    end)
  end
  local stat = uv.fs_stat(path)
  if stat then
    if stat.type ~= "file" then report(s, "目标不是源码文件: " .. path); done(); return end
    vim.ui.select({ "使用现有源码并关联", "另选路径", "取消" }, {prompt="源码已存在，保留其内容: " .. path}, accept)
  else accept("创建") end
end

local function single_problem(s, task, done)
  local path, err = eval_path(s.cfg.received_problems_path, task, s.cfg.received_files_extension, s)
  if not path then report(s, err); done(); return end
  local function selected(value)
    if not alive(s) then return end
    if not value or value == "" then done(); return end
    create_source(s, task, value, s.cfg.open_received_problems, done)
  end
  if s.cfg.received_problems_prompt_path then vim.ui.input({prompt="新题源码路径: ", default=path, completion="file"}, selected) else selected(path) end
end

local function contest(s, tasks, done)
  local directory, err = eval_path(s.cfg.received_contests_directory, tasks[1], s.cfg.received_files_extension, s)
  if not directory then report(s, err); done(); return end
  local function selected_dir(value)
    if not alive(s) then return end
    if not value or value == "" then done(); return end
    if value:sub(1,1) ~= "/" then value = s.cwd .. "/" .. value end
    local function selected_extension(extension)
      if not alive(s) then return end
      if not extension then done(); return end
      if not extension:match("^[%w_+%-]+$") or #extension > 32 then report(s, "无效源码扩展名"); done(); return end
      local i = 0
      local function next_task()
        if not alive(s) then return end
        i = i + 1; if not tasks[i] then done(); return end
        local relative, why = eval_path(s.cfg.received_contests_problems_path, tasks[i], extension, s)
        if not relative then report(s, why); next_task(); return end
        if relative:sub(1,1) == "/" or ("/" .. relative .. "/"):find("/../", 1, true) then report(s, "比赛题目路径必须位于选择的比赛目录内"); next_task(); return end
        create_source(s, tasks[i], value .. "/" .. relative, s.cfg.open_received_contests, next_task)
      end
      next_task()
    end
    if s.cfg.received_contests_prompt_extension then vim.ui.input({prompt="比赛源码扩展名: ", default=s.cfg.received_files_extension}, selected_extension)
    else selected_extension(s.cfg.received_files_extension) end
  end
  if s.cfg.received_contests_prompt_directory then vim.ui.input({prompt="比赛源码目录: ", default=directory, completion="dir"}, selected_dir)
  else selected_dir(directory) end
end

function M.process(s)
  if not alive(s) or s.busy or #s.queue == 0 then return end
  s.busy = true
  local tasks = table.remove(s.queue, 1)
  local function done() finish(s) end
  local function current_task()
    if not s.target then report(s, "请从具名 C++ 源码启动接收，或选择完整题目"); done(); return end
    import(s, tasks[1], s.target.path, function() return s.core.valid_target(s.target) end, done)
  end
  if s.mode == "testcases" then current_task()
  elseif s.mode == "problem" then single_problem(s, tasks[1], done)
  elseif s.mode == "contest" or #tasks > 1 then contest(s, tasks, done)
  else
    vim.ui.select({"仅样例（发起接收的源码）", "完整题目", "取消"}, {prompt=tasks[1].name}, function(choice)
      if not alive(s) then return end
      if choice == "仅样例（发起接收的源码）" then current_task()
      elseif choice == "完整题目" then single_problem(s, tasks[1], done) else done() end
    end)
  end
end

local function collect(s, task)
  if not alive(s) then return nil, "接收已停止" end
  local key = task.batch.id
  if s.completed[key] then return true end
  local batch = s.batches[key]
  if not batch then
    if vim.tbl_count(s.batches) >= 32 then return nil, "未完成批次过多" end
    batch = { size = task.batch.size, tasks = {}, count = 0, timer = uv.new_timer() }
    s.batches[key] = batch
    batch.timer:start(s.opts.batch_timeout_ms or 60000, 0, vim.schedule_wrap(function()
      if not alive(s) then return end
      s.batches[key] = nil; close(batch.timer)
      s.core.notify("接收批次超时 " .. key .. "（" .. batch.count .. "/" .. batch.size .. "），可重新发送", vim.log.levels.WARN)
    end))
  elseif batch.size ~= task.batch.size then return nil, "同一 batch.id 的 size 不一致" end
  if not batch.tasks[task._id] then batch.count = batch.count + 1 end
  batch.tasks[task._id] = task
  if batch.count == batch.size then
    if #s.queue >= 32 then return nil, "待处理批次过多" end
    close(batch.timer); s.batches[key] = nil
    local tasks = {}; for _, t in pairs(batch.tasks) do tasks[#tasks + 1] = t end
    table.sort(tasks, function(a,b) return a._id < b._id end)
    s.completed[key] = true; s.completed_order[#s.completed_order + 1] = key
    if #s.completed_order > 1024 then s.completed[table.remove(s.completed_order, 1)] = nil end
    s.queue[#s.queue + 1] = tasks
    vim.schedule(function() if alive(s) then M.process(s) end end)
  end
  return true
end

local reasons = { [202]="Accepted", [204]="No Content", [400]="Bad Request", [405]="Method Not Allowed", [408]="Request Timeout", [413]="Payload Too Large", [431]="Request Header Fields Too Large", [503]="Service Unavailable" }
local function disconnect(s, c)
  close(c.timer); close(c.socket); s.connections[c] = nil
end
local function respond(s, c, code, body)
  if c.replied or c.socket:is_closing() then return end
  c.replied = true; c.socket:read_stop(); close(c.timer)
  body = body or ""
  local response = "HTTP/1.1 " .. code .. " " .. reasons[code] .. "\r\nConnection: close\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: POST, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body
  c.socket:write(response, function() disconnect(s, c) end)
end

local function receive_bytes(s, c, chunk)
  if not alive(s) or c.replied then return end
  c.buffer = c.buffer .. chunk
  if not c.length then
    local boundary = c.buffer:find("\r\n\r\n", 1, true)
    if (boundary and boundary + 3 > s.header_limit) or (not boundary and #c.buffer > s.header_limit) then respond(s,c,431,"header too large"); return end
    if not boundary then return end
    local headers = c.buffer:sub(1, boundary - 1)
    local first, rest = headers:match("^([^\r\n]+)\r\n(.*)$")
    first, rest = first or headers, rest or ""
    local method = first:match("^(%u+) [^ ]+ HTTP/1%.[01]$")
    if not method then respond(s,c,400,"invalid request line"); return end
    if method == "OPTIONS" then respond(s,c,204); return end
    if method ~= "POST" then respond(s,c,405,"POST required"); return end
    local lengths, transfer = {}, false
    for line in (rest .. "\r\n"):gmatch("(.-)\r\n") do
      local name, value = line:match("^([%w-]+):%s*(.-)%s*$")
      if not name then respond(s,c,400,"invalid header"); return end
      if name:lower() == "content-length" then lengths[#lengths + 1] = value end
      if name:lower() == "transfer-encoding" then transfer = true end
    end
    if transfer or #lengths ~= 1 or not lengths[1]:match("^%d+$") then respond(s,c,400,"one Content-Length required; chunked transfer unsupported"); return end
    c.length = tonumber(lengths[1])
    if c.length > s.body_limit then respond(s,c,413,"body too large"); return end
    c.buffer = c.buffer:sub(boundary + 4)
  end
  if #c.buffer > s.body_limit then respond(s,c,413,"body too large"); return end
  if #c.buffer < c.length then return end
  if #c.buffer > c.length then respond(s,c,400,"extra bytes after body"); return end
  c.socket:read_stop()
  vim.schedule(function()
    if not alive(s) or c.replied then return end
    local ok, task = pcall(vim.json.decode, c.buffer)
    if not ok then respond(s,c,400,"invalid JSON"); report(s,"接收 JSON 解析失败"); return end
    local validated, err = M.validate(task)
    if not validated then respond(s,c,400,err); report(s,err); return end
    if (s.mode == "testcases" or s.mode == "problem") and validated.batch.size ~= 1 then respond(s,c,400,"use receive contest for a batch"); return end
    local accepted, why = collect(s, validated)
    if not accepted then respond(s,c,503,why); report(s,why); return end
    respond(s,c,202,"queued")
  end)
end

function M.start(mode, buf, core)
  if not ({ testcases=true, problem=true, contest=true, persistently=true })[mode] then local err="接收模式应为 testcases/problem/contest/persistently"; core.notify(err,vim.log.levels.ERROR); return nil,err end
  if session then local err="接收器已在运行，请先 CPCache receive stop"; core.notify(err,vim.log.levels.ERROR); return nil,err end
  local target, err = core.capture(buf)
  if mode == "testcases" and not target then core.notify(err,vim.log.levels.ERROR); return nil,err end
  local opts, cfg = core.options(), target and adapter.config(target.buf) or adapter.receiver_config()
  local port = opts.port or cfg.companion_port
  if type(port) ~= "number" or port < 0 or port > 65535 or port % 1 ~= 0 then core.notify("无效接收端口",vim.log.levels.ERROR); return nil,"无效接收端口" end
  local s = { core=core, store=assert(core.store()), cfg=vim.deepcopy(cfg), opts=opts, cwd=vim.fn.getcwd(), target=target,
    mode=mode, connections={}, batches={}, queue={}, completed={}, completed_order={}, busy=false, active=true,
    header_limit=opts.header_limit or 16384, body_limit=opts.body_limit or 8*1024*1024, server=uv.new_tcp() }
  local bound, why = s.server:bind("127.0.0.1", port)
  if not bound then close(s.server); err="无法监听 127.0.0.1:" .. port .. "（请停止其他接收器）: " .. tostring(why); report(s,err); return nil,err end
  session = s
  local listening, lerr = s.server:listen(32, function(accept_error)
    if accept_error or not alive(s) then return end
    local c = { socket=uv.new_tcp(), timer=uv.new_timer(), buffer="" }
    local accepted = s.server:accept(c.socket)
    if not accepted then disconnect(s,c); return end
    s.connections[c] = true
    if vim.tbl_count(s.connections) > 32 then respond(s,c,503,"too many connections"); return end
    local function timeout() respond(s,c,408,"idle timeout") end
    c.timer:start(opts.idle_timeout_ms or 10000, 0, timeout)
    c.socket:read_start(function(readerr, data)
      if readerr or not data then disconnect(s,c); return end
      if c.timer:is_closing() then return end
      c.timer:start(opts.idle_timeout_ms or 10000, 0, timeout)
      local ok, parseerr = pcall(receive_bytes,s,c,data)
      if not ok then respond(s,c,400,"request processing failed"); vim.schedule(function() report(s,tostring(parseerr)) end) end
    end)
  end)
  if not listening then M.stop(); err="启动监听失败: " .. tostring(lerr); report(s,err); return nil,err end
  s.port = s.server:getsockname().port
  core.notify("等待 Competitive Companion: 127.0.0.1:" .. s.port .. "（" .. mode .. "）")
  return true
end

function M.stop(graceful)
  local s = session; if not s then return true end
  s.active = false; session = nil; close(s.server)
  for c in pairs(s.connections) do if not graceful or not c.replied then disconnect(s,c) end end
  for _, batch in pairs(s.batches) do close(batch.timer) end
  s.queue, s.batches = {}, {}
  return true
end

function M.status()
  local s = session
  if not s then return "接收器未运行", { active=false } end
  return "接收 " .. s.mode .. " @ 127.0.0.1:" .. s.port, { active=true, port=s.port, mode=s.mode, batches=vim.tbl_count(s.batches), queued=#s.queue, busy=s.busy }
end
return M
