local M = { root = assert(vim.env.CP_CACHE_TEST_ROOT) }
function M.write(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local f = assert(io.open(path, "wb"))
  assert(f:write(data))
  assert(f:close())
end
function M.read(path)
  local f = assert(io.open(path, "rb"))
  local data = assert(f:read("*a")); assert(f:close()); return data
end
function M.source(name, text)
  local path = M.root .. "/fixtures/" .. name
  M.write(path, text or '#include <iostream>\nint main(){long long n,x,s=0; std::cin>>n; while(n-- && std::cin>>x)s+=x; std::cout<<s<<"\\n";}\n')
  vim.cmd.edit(vim.fn.fnameescape(path))
  vim.bo.filetype = "cpp"
  return vim.api.nvim_get_current_buf(), path
end
function M.await(predicate, message, timeout)
  assert(vim.wait(timeout or 15000, predicate, 10), message or "timeout")
end
function M.done(runner)
  M.await(function()
    for _, tc in pairs(runner.tcdata) do if tc.status == "RUNNING" or tc.status == "" or tc.running then return false end end
    return true
  end, "runner did not complete", 30000)
  vim.wait(60)
end
function M.snapshot(directory)
  local result = {}
  local function visit(path, prefix)
    local scan = assert(vim.uv.fs_scandir(path))
    while true do
      local name, kind = vim.uv.fs_scandir_next(scan); if not name then break end
      local key = prefix .. name
      if kind == "directory" then result[key .. "/"] = true; visit(path .. "/" .. name, key .. "/")
      elseif kind == "link" then result[key] = "link:" .. assert(vim.uv.fs_readlink(path .. "/" .. name))
      else result[key] = vim.fn.sha256(M.read(path .. "/" .. name)) end
    end
  end
  visit(directory, ""); return result
end
function M.finish(fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then print(err); vim.cmd("cquit 1") else vim.cmd("qa!") end
end
function M.map(buf, key)
  local map = vim.api.nvim_buf_call(buf, function() return vim.fn.maparg(key, "n", false, true) end)
  assert(map.callback, "missing callback mapping: " .. key)
  map.callback()
end
return M
