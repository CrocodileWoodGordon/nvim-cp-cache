local Store = require("cp_cache.store")
local s = assert(Store.new(assert(vim.env.CP_CACHE_WORKER_ROOT)))
local p = assert(s:get("cf-1234-A"))
if vim.env.CP_CACHE_WORKER_REV then
  p.name = "worker " .. vim.uv.os_getpid()
  local saved, err = s:save(p, tonumber(vim.env.CP_CACHE_WORKER_REV))
  if not saved then
    assert(err:find("冲突") or err:find("正在被写入"), err)
    print("CONFLICT: " .. err)
    vim.cmd("cquit 2")
  end
else
  assert(p.tests[1].input == "中文\r\n\n")
end
vim.cmd("qa!")
