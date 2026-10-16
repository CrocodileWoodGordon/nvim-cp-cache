local M = {}
function M.open(store, choose, notify, force_fallback)
  local entries, err, errors = store:list()
  if not entries then notify(err, vim.log.levels.ERROR); return end
  for _, why in ipairs(errors) do notify(why, vim.log.levels.WARN) end
  if #entries == 0 then notify("缓存题库为空"); return end
  local function label(p) return p.id .. "  " .. p.name .. "  " .. (p.group or "") .. "  " .. (p.url or "") end
  local ok, pickers = pcall(require, "telescope.pickers")
  if force_fallback or not ok then
    vim.ui.select(entries, { prompt = "选择缓存题目（样例共享）", format_item = label }, choose)
    return
  end
  local actions, state = require("telescope.actions"), require("telescope.actions.state")
  pickers.new({}, {
    prompt_title = "缓存题目：题号 / 标题 / URL",
    finder = require("telescope.finders").new_table({ results = entries, entry_maker = function(p)
      return { value = p, display = label(p), ordinal = label(p) }
    end }),
    sorter = require("telescope.config").values.generic_sorter({}),
    attach_mappings = function(prompt)
      actions.select_default:replace(function()
        local selected = state.get_selected_entry()
        actions.close(prompt); if selected then choose(selected.value) end
      end)
      return true
    end,
  }):find()
end
return M
