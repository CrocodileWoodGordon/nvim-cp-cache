local M = {}
local uv = vim.uv or vim.loop

function M.valid_id(id)
  if type(id) ~= "string" then return false end
  if id:match("^cf%-%d+%-%u[%u%d]*$") or id:match("^cf%-gym%-%d+%-%u[%u%d]*$") then return true end
  local hash = id:match("^url%-(%x+)$") or id:match("^local%-(%x+)$")
  return hash ~= nil and #hash == 64 and hash == hash:lower()
end

function M.source(source)
  if type(source) == "number" then
    if not vim.api.nvim_buf_is_valid(source) then return nil, "源码 buffer 已关闭" end
    source = vim.api.nvim_buf_get_name(source)
  end
  if type(source) ~= "string" or source == "" or source:find("%z") then return nil, "需要具名源码路径" end
  local path = vim.fs.normalize(vim.fn.fnamemodify(source, ":p")):gsub("/$", "")
  local real = uv.fs_realpath(path)
  if real then return real end
  -- Resolve the nearest existing parent, including not-yet-created subdirectories.
  local tail, parent = {}, path
  while parent ~= "/" and not uv.fs_realpath(parent) do
    table.insert(tail, 1, vim.fs.basename(parent))
    parent = vim.fs.dirname(parent)
  end
  real = uv.fs_realpath(parent)
  if not real then return nil, "无法解析源码父目录: " .. parent end
  return (real == "/" and "" or real) .. "/" .. table.concat(tail, "/")
end

function M.source_key(source)
  local path, err = M.source(source)
  if not path then return nil, err end
  return vim.fn.sha256(path), path
end

function M.url(url)
  if type(url) ~= "string" or #url > 8192 or url:find("[%c%s]") then return nil, "URL 必须是有效的 HTTP(S) 地址" end
  local scheme, authority, rest = url:match("^([%a][%w+.-]*)://([^/?#]+)(.*)$")
  if not scheme or not ({ http = true, https = true })[scheme:lower()] or authority:find("@", 1, true) then
    return nil, "URL 必须是无用户名的 HTTP(S) 地址"
  end
  scheme, authority = scheme:lower(), authority:lower()
  local host, port
  if authority:sub(1, 1) == "[" then
    host, port = authority:match("^(%[[%x:%.]+%]):?(%d*)$")
  else
    host, port = authority:match("^([%w.-]+):?(%d*)$")
  end
  if not host or host:match("^%.") or host:match("%.$") or host:find("..", 1, true)
    or (port ~= "" and (tonumber(port) < 1 or tonumber(port) > 65535)) then return nil, "无效 URL 主机或端口" end
  rest = rest:gsub("#.*$", "")
  local normalized = scheme .. "://" .. authority .. rest
  -- Only these exact official hosts participate in Codeforces identities.
  if (host == "codeforces.com" or host == "www.codeforces.com") and
    (port == "" or port == (scheme == "https" and "443" or "80")) then
    local path = rest:match("^[^?]*")
    local contest, letter = path:match("^/contest/(%d+)/problem/([%a%d]+)/?$")
    if not contest then contest, letter = path:match("^/problemset/problem/(%d+)/([%a%d]+)/?$") end
    local gym, gymletter = path:match("^/gym/(%d+)/problem/([%a%d]+)/?$")
    if gym and M.valid_id("cf-gym-" .. gym .. "-" .. gymletter:upper()) then
      return "cf-gym-" .. gym .. "-" .. gymletter:upper(), "https://codeforces.com/gym/" .. gym .. "/problem/" .. gymletter:upper()
    end
    if contest then
      local id = "cf-" .. contest .. "-" .. letter:upper()
      if M.valid_id(id) then return id, "https://codeforces.com/problemset/problem/" .. contest .. "/" .. letter:upper() end
    end
  end
  return "url-" .. vim.fn.sha256(normalized), normalized
end

function M.problem(url, source)
  if url ~= nil and url ~= "" then return M.url(url) end
  local key, path = M.source_key(source)
  if not key then return nil, path end
  return "local-" .. key
end

return M
