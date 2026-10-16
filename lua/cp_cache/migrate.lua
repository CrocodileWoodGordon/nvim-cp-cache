local M = {}
local adapter = require("cp_cache.adapter")
local identity = require("cp_cache.identity")
local uv = vim.uv or vim.loop

function M.read(path)
  local fd, err = uv.fs_open(path, "r", 384)
  if not fd then if tostring(err):find("ENOENT", 1, true) then return nil end; return nil, "读取失败 " .. path .. ": " .. tostring(err) end
  local stat, serr = uv.fs_fstat(fd)
  if not stat or stat.type ~= "file" or stat.size > 64 * 1024 * 1024 then uv.fs_close(fd); return nil, "无效或过大的文件 " .. path .. ": " .. tostring(serr) end
  local data, why = uv.fs_read(fd, stat.size, 0)
  local ok, cerr = uv.fs_close(fd)
  if not data or not ok then return nil, "读取/关闭失败 " .. path .. ": " .. tostring(why or cerr) end
  if #data ~= stat.size then return nil, "读取时文件长度变化，请重试: " .. path end
  return data
end

local function pattern(source, format)
  local parts = vim.split(format, "$(TCNUM)", { plain = true })
  if #parts < 2 then return nil, "旧样例格式缺少 $(TCNUM)" end
  for i, part in ipairs(parts) do
    local evaluated = adapter.eval_file(source, part)
    if not evaluated then return nil, "不能解析旧样例命名格式" end
    parts[i] = evaluated:gsub("([^%w])", "%%%1")
  end
  return "^" .. table.concat(parts, "(%d+)") .. "$"
end

function M.legacy(buf, source, mode)
  local cfg = adapter.config(buf)
  local directory = vim.fs.dirname(source) .. "/" .. cfg.testcases_directory
  local single = adapter.eval_file(source, cfg.testcases_single_file_format)
  if not single then return nil, "不能解析旧 msgpack 文件名" end
  local packed, err = M.read(directory .. "/" .. single)
  if err then return nil, err end
  local files = {}
  local inp, ierr = pattern(source, cfg.testcases_input_file_format); if not inp then return nil, ierr end
  local outp, oerr = pattern(source, cfg.testcases_output_file_format); if not outp then return nil, oerr end
  local scan, scanerr = uv.fs_scandir(directory)
  if not scan and not tostring(scanerr):find("ENOENT", 1, true) then return nil, "扫描旧样例失败: " .. tostring(scanerr) end
  if scan then
    while true do
      local name, kind = uv.fs_scandir_next(scan); if not name then break end
      local n, field = name:match(inp), "input"
      if not n then n, field = name:match(outp), "output" end
      if n and (kind == "file" or kind == "link") then
        n = tonumber(n)
        local data, why = M.read(directory .. "/" .. name)
        if not data then return nil, why or "旧样例在读取时消失: " .. name end
        files[n] = files[n] or {}; files[n][field] = data
      end
    end
  end
  if not mode and packed and next(files) then return nil, "同时发现文本和 msgpack，请指定 CPCache migrate files 或 msgpack" end
  if mode == "msgpack" or (not mode and packed) then
    if not packed then return nil, "没有旧 msgpack 样例" end
    local ok, decoded = pcall(vim.mpack.decode, packed)
    if not ok or type(decoded) ~= "table" then return nil, "旧 msgpack 损坏: " .. tostring(decoded) end
    files = decoded
  elseif mode and mode ~= "files" then return nil, "迁移格式应为 files 或 msgpack" end
  local tests = {}
  for number, case in pairs(files) do
    if type(number) ~= "number" or number < 0 or number % 1 ~= 0 or type(case) ~= "table"
      or (case.input ~= nil and type(case.input) ~= "string") or (case.output ~= nil and type(case.output) ~= "string") then return nil, "无效旧样例数据" end
    tests[#tests + 1] = { id = number, input = case.input or "", output = case.output, origin = "migrated" }
  end
  table.sort(tests, function(a,b) return a.id < b.id end)
  if #tests == 0 then return nil, "没有找到此源码的旧样例" end
  return tests
end

function M.copy(store, buf, source, mode)
  local current, err = store:for_source(source)
  if err then return nil, err end
  if current then return nil, "当前源码已有缓存关联；迁移不会覆盖它（即使样例为空）" end
  local tests, why = M.legacy(buf, source, mode); if not tests then return nil, why end
  local id = assert(identity.problem(nil, source))
  local old, oerr = store:get(id); if oerr then return nil, oerr end
  if old then return nil, "此源码的手工题目已在库中，请搜索重新关联" end
  local p, perr = store:save({ id = id, name = vim.fs.basename(source), tests = tests }, 0)
  if not p then return nil, perr end
  local check, cerr = store:get(id)
  if not check or not vim.deep_equal(check.tests, tests) then return nil, cerr or "迁移回读校验失败；未建立关联" end
  local bound, berr = store:bind(source, id)
  if not bound then return nil, "题目已复制，但源码关联失败: " .. tostring(berr) end
  local _, indexerr = store:list(); if indexerr then return nil, "迁移已保存，但索引失败: " .. indexerr end
  return check
end

function M.export(store, source, mode)
  local p, err = store:for_source(source); if not p then return nil, err or "当前源码没有题目关联" end
  local directory = store.root .. "/exports/" .. p.id
  local ok, why = store:mkdir(directory); if not ok then return nil, why end
  if mode == "auto" then
    local last, lerr = store:read_json(directory .. "/last.json"); if lerr then return nil, lerr end
    mode = last and last.format == "msgpack" and "files" or "msgpack"
  end
  if mode ~= "files" and mode ~= "msgpack" then return nil, "导出格式应为 files 或 msgpack" end
  local path = directory .. "/" .. mode .. "-r" .. p.revision
  if mode == "msgpack" then
    path = path .. ".msgpack"
    local tests, terr = store:testcases(source); if not tests then return nil, terr end
    ok, why = store:atomic(path, vim.mpack.encode(tests))
  else
    ok, why = store:mkdir(path)
    if ok then
      for _, tc in ipairs(p.tests) do
        ok, why = store:atomic(path .. "/" .. p.id .. "." .. tc.id .. ".in", tc.input)
        if not ok then break end
        if tc.output ~= nil then ok, why = store:atomic(path .. "/" .. p.id .. "." .. tc.id .. ".out", tc.output) end
        if not ok then break end
      end
    end
  end
  if not ok then return nil, why end
  local wrote, werr = store:write_json(directory .. "/last.json", { format = mode, revision = p.revision })
  if not wrote then return nil, werr end
  return path
end

return M
