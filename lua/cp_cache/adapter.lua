-- CompetiTest exports are version-sensitive. Keep every dependency call here.
local M = {}
local api = vim.api
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
  local runner = M.runners()[buf]
  if not runner then return end
  -- Upstream kill_all_processes alone starts queued tests from exit callbacks.
  runner.next_tc = math.huge
  runner:kill_all_processes()
  if runner.ui then runner.ui:delete() end
  M.runners()[buf] = nil
end

function M.editor_widget(buf, number, input, output, callback, win)
  M.config(buf)
  dependency("widgets").editor(buf, number, input, output, callback, win or api.nvim_get_current_win())
end

function M.picker_widget(buf, tests, title, callback, win)
  M.config(buf)
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
