local identity = require("cp_cache.identity")
local uv = vim.uv or vim.loop
local Store = {}
Store.__index = Store
local function fail(stage, path, err) return nil, stage .. " [" .. path .. "]: " .. tostring(err) end
local function integer(n) return type(n) == "number" and n >= 0 and n < 2^53 and n % 1 == 0 end
local function missing(err) return err and tostring(err):find("ENOENT", 1, true) end

-- All cache I/O rejects symlinks, including ancestors of a configured cache root.
function Store:safe(path)
  if path ~= self.root and path:sub(1, #self.root + 1) ~= self.root .. "/" then return fail("路径越过缓存根目录", path, "refused") end
  local current = ""
  for part in path:gmatch("[^/]+") do
    if part == ".." or part == "." then return fail("非法缓存路径", path, part) end
    current = current .. "/" .. part
    local stat, err = uv.fs_lstat(current)
    if stat and stat.type == "link" then return fail("缓存路径含符号链接", current, "refused") end
    if not stat and not missing(err) then return fail("检查路径失败", current, err) end
  end
  return true
end

function Store:mkdir(path)
  local ok, err = self:safe(path); if not ok then return nil, err end
  local current = ""
  for part in path:gmatch("[^/]+") do
    current = current .. "/" .. part
    local stat = uv.fs_lstat(current)
    if not stat then
      local made, why = uv.fs_mkdir(current, 448)
      if not made and not tostring(why):find("EEXIST", 1, true) then return fail("创建目录失败", current, why) end
      local checked, checkerr = self:safe(path); if not checked then return nil, checkerr end
    elseif stat.type ~= "directory" then return fail("不是目录", current, stat.type) end
  end
  return true
end

function Store.new(root)
  if type(root) ~= "string" or root == "" or root:find("%z") then return nil, "无效缓存根目录" end
  root = vim.fs.normalize(vim.fn.fnamemodify(root, ":p")):gsub("/$", "")
  if root == "" or root == "/" then return nil, "缓存根目录不能是 /" end
  local self = setmetatable({ root = root }, Store)
  for _, dir in ipairs({ "problems", "bindings", "locks", "exports" }) do
    local ok, err = self:mkdir(root .. "/" .. dir); if not ok then return nil, err end
  end
  return self
end

function Store:read_bytes(path)
  local ok, err = self:safe(path); if not ok then return nil, err end
  local fd, why = uv.fs_open(path, "r", 384)
  if not fd then if missing(why) then return nil end; return fail("读取失败", path, why) end
  local stat, sterr = uv.fs_fstat(fd)
  if not stat or stat.type ~= "file" or stat.size > 64 * 1024 * 1024 then
    uv.fs_close(fd); return fail("无效或过大的缓存文件", path, sterr or "64 MiB limit")
  end
  local data, rerr = uv.fs_read(fd, stat.size, 0)
  local closed, cerr = uv.fs_close(fd)
  if not data then return fail("读取失败", path, rerr) end
  if not closed then return fail("关闭文件失败", path, cerr) end
  return data
end

function Store:read_json(path)
  local data, err = self:read_bytes(path)
  if not data then return nil, err end
  local ok, object = pcall(vim.json.decode, data)
  if not ok or type(object) ~= "table" then return fail("JSON 损坏", path, object) end
  return object
end

function Store:atomic(path, bytes)
  local ok, err = self:safe(path); if not ok then return nil, err end
  local temporary = path .. "." .. uv.os_getpid() .. "." .. tostring(uv.hrtime()) .. ".tmp"
  local fd, why = uv.fs_open(temporary, "wx", 384)
  if not fd then return fail("创建临时文件失败", temporary, why) end
  local offset = 0
  while offset < #bytes do
    local count, werr = uv.fs_write(fd, bytes:sub(offset + 1), offset)
    if not count or count == 0 then
      uv.fs_close(fd); uv.fs_unlink(temporary); return fail("写入失败", temporary, werr)
    end
    offset = offset + count
  end
  local synced, serr = uv.fs_fsync(fd)
  local closed, cerr = uv.fs_close(fd)
  if not synced or not closed then uv.fs_unlink(temporary); return fail("刷新/关闭失败", temporary, serr or cerr) end
  ok, err = self:safe(path)
  if not ok then uv.fs_unlink(temporary); return nil, err end
  local renamed, rerr = uv.fs_rename(temporary, path)
  if not renamed then uv.fs_unlink(temporary); return fail("原子替换失败", path, rerr) end
  return true
end

function Store:write_json(path, object)
  local ok, data = pcall(vim.json.encode, object)
  if not ok then return fail("JSON 编码失败", path, data) end
  return self:atomic(path, data .. "\n")
end

function Store:unlink(path)
  local ok, err = self:safe(path); if not ok then return nil, err end
  local removed, why = uv.fs_unlink(path)
  if not removed and not missing(why) then return fail("删除失败", path, why) end
  return true
end

function Store:locked(key, fn)
  if not key:match("^[%w-]+$") then return nil, "非法锁 ID" end
  local path = self.root .. "/locks/" .. key .. ".lock"
  local ok, err = self:safe(path); if not ok then return nil, err end
  local fd, why = uv.fs_open(path, "wx", 384)
  if not fd then return fail("缓存正在被写入，请重试；死锁可用 CPCache unlock 恢复", path, why) end
  local token = tostring(uv.hrtime())
  local wrote, werr = uv.fs_write(fd, vim.json.encode({ pid = uv.os_getpid(), token = token }), 0)
  local closed, cerr = uv.fs_close(fd)
  if not wrote or not closed then self:unlink(path); return fail("写锁失败", path, werr or cerr) end
  local success, result, detail = pcall(fn)
  local released, rerr = self:unlink(path)
  if not success then return nil, "缓存操作失败: " .. tostring(result) end
  if not released then return nil, rerr end
  return result, detail
end

-- Never steal a lock merely because it is old. A live or unknown owner refuses recovery.
function Store:unlock(id)
  if not identity.valid_id(id) then return nil, "非法题目 ID" end
  local path = self.root .. "/locks/problem-" .. id .. ".lock"
  local owner, err = self:read_json(path)
  if not owner then return nil, err or "没有需要恢复的锁" end
  if not integer(owner.pid) or owner.pid < 1 then return nil, "锁的 PID 无效；请人工检查 " .. path end
  local alive, why = uv.kill(owner.pid, 0)
  if alive or not tostring(why):find("ESRCH", 1, true) then return nil, "锁的进程仍在运行或状态未知，拒绝解锁: " .. owner.pid end
  return self:unlink(path)
end

function Store:problem_path(id)
  if not identity.valid_id(id) then return nil, "非法题目 ID: " .. tostring(id) end
  return self.root .. "/problems/" .. id .. ".json"
end

function Store.validate(problem, id)
  if type(problem) ~= "table" or problem.schema_version ~= 1 then return nil, "不支持的题目 schema_version" end
  if not identity.valid_id(problem.id) or (id and id ~= problem.id) then return nil, "题目 ID 与文件不一致" end
  if not integer(problem.revision) or problem.revision < 1 then return nil, "无效 revision" end
  if type(problem.name) ~= "string" or type(problem.tests) ~= "table" or not vim.islist(problem.tests) then return nil, "无效题目标题或 tests 数组" end
  for _, key in ipairs({ "group", "url", "canonical_url", "updated_at" }) do
    if problem[key] ~= nil and type(problem[key]) ~= "string" then return nil, "无效字段: " .. key end
  end
  local ids = {}
  for _, tc in ipairs(problem.tests) do
    if type(tc) ~= "table" or not integer(tc.id) or ids[tc.id] or type(tc.input) ~= "string"
      or (tc.output ~= nil and type(tc.output) ~= "string")
      or (tc.origin ~= nil and tc.origin ~= "manual" and tc.origin ~= "received" and tc.origin ~= "migrated") then return nil, "无效或重复样例 ID/input/output/origin" end
    ids[tc.id] = true
  end
  return true
end

function Store:get(id)
  local path, err = self:problem_path(id); if not path then return nil, err end
  local problem, why = self:read_json(path); if not problem then return nil, why end
  local ok, verr = Store.validate(problem, id); if not ok then return fail("题目校验失败", path, verr) end
  return problem
end

function Store:save(problem, expected)
  local path, err = self:problem_path(problem.id); if not path then return nil, err end
  return self:locked("problem-" .. problem.id, function()
    local old, why = self:get(problem.id); if why then return nil, why end
    local revision = old and old.revision or 0
    if expected ~= revision then return nil, "样例已被其他操作修改（revision 冲突），请重新打开编辑器/重试" end
    local next_problem = vim.deepcopy(problem)
    next_problem.schema_version, next_problem.revision = 1, revision + 1
    next_problem.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local valid, verr = Store.validate(next_problem); if not valid then return nil, verr end
    local wrote, werr = self:write_json(path, next_problem); if not wrote then return nil, werr end
    return next_problem
  end)
end

function Store:binding(source)
  local key, path = identity.source_key(source); if not key then return nil, path end
  local binding, err = self:read_json(self.root .. "/bindings/" .. key .. ".json")
  if not binding then return nil, err end
  if binding.schema_version ~= 1 or binding.source ~= path or not identity.valid_id(binding.problem_id) then return nil, "源码关联损坏或 schema_version 不支持: " .. path end
  return binding
end

function Store:for_source(source)
  local binding, err = self:binding(source); if not binding then return nil, err end
  local problem, why = self:get(binding.problem_id)
  return problem, why or (not problem and "关联的题目不存在: " .. binding.problem_id or nil), binding
end

function Store:bind(source, id)
  local key, path = identity.source_key(source); if not key then return nil, path end
  if not identity.valid_id(id) then return nil, "非法题目 ID" end
  return self:locked("problem-" .. id, function()
    local problem, err = self:get(id); if not problem then return nil, err or "题目不存在" end
    return self:locked("binding-" .. key, function()
      local _, why = self:binding(path); if why then return nil, why end
      local binding = { schema_version = 1, source = path, problem_id = id }
      local ok, werr = self:write_json(self.root .. "/bindings/" .. key .. ".json", binding)
      if not ok then return nil, werr end
      return binding
    end)
  end)
end

function Store:forget(source)
  local key, path = identity.source_key(source); if not key then return nil, path end
  return self:locked("binding-" .. key, function()
    local _, err = self:binding(path); if err then return nil, err end
    return self:unlink(self.root .. "/bindings/" .. key .. ".json")
  end)
end

function Store:scan(directory)
  local path = self.root .. "/" .. directory
  local ok, err = self:safe(path); if not ok then return nil, err end
  local scan, why = uv.fs_scandir(path); if not scan then return fail("扫描失败", path, why) end
  local names = {}
  while true do
    local name, kind = uv.fs_scandir_next(scan); if not name then break end
    if name:match("%.json$") then
      if kind == "link" then return fail("缓存目录含符号链接", path .. "/" .. name, "refused") end
      names[#names + 1] = name
    end
  end
  table.sort(names)
  return names
end

function Store:list()
  local names, err = self:scan("problems"); if not names then return nil, err end
  local entries, errors = {}, {}
  for _, name in ipairs(names) do
    local id = name:sub(1, -6)
    local p, why = self:get(id)
    if p then entries[#entries + 1] = { id = p.id, name = p.name, group = p.group, url = p.url,
      canonical_url = p.canonical_url, updated_at = p.updated_at, count = #p.tests }
    else errors[#errors + 1] = why or ("找不到题目: " .. id) end
  end
  local ok, why = self:write_json(self.root .. "/index.json", { schema_version = 1, problems = entries })
  if not ok then return nil, why end
  return entries, nil, errors
end

function Store:bindings(id)
  local names, err = self:scan("bindings"); if not names then return nil, err end
  local bindings = {}
  for _, name in ipairs(names) do
    local b, why = self:read_json(self.root .. "/bindings/" .. name)
    if not b then return nil, why or "关联文件消失，请重试" end
    if b.schema_version ~= 1 or type(b.source) ~= "string" or vim.fn.sha256(b.source) .. ".json" ~= name or not identity.valid_id(b.problem_id) then return nil, "损坏的关联: " .. name end
    if b.problem_id == id then bindings[#bindings + 1] = b end
  end
  return bindings
end

function Store:remove(id, expected)
  local path, err = self:problem_path(id); if not path then return nil, err end
  return self:locked("problem-" .. id, function()
    local p, why = self:get(id); if not p then return nil, why or "题目不存在" end
    if expected ~= p.revision then return nil, "题目已变化，请重新确认删除" end
    local bindings, berr = self:bindings(id); if not bindings then return nil, berr end
    for _, b in ipairs(bindings) do
      local ok, ferr = self:locked("binding-" .. vim.fn.sha256(b.source), function()
        local now, nerr = self:binding(b.source); if nerr then return nil, nerr end
        if now and now.problem_id == id then return self:unlink(self.root .. "/bindings/" .. vim.fn.sha256(b.source) .. ".json") end
        return true
      end)
      if not ok then return nil, ferr end
    end
    return self:unlink(path)
  end)
end

function Store:testcases(source)
  local p, err = self:for_source(source)
  if not p then if err then return nil, err end; return {} end
  local tests = {}
  for _, tc in ipairs(p.tests) do tests[tc.id] = { input = tc.input, output = tc.output } end
  return tests
end

return Store
