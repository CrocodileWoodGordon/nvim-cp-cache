"""Narrow, reproducible integration with this repository's documented NvChad host."""
def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError("Host config differs from the reviewed version: " + old[:70])
    return text.replace(old, new, 1)


def update(name, text):
    if name == "lua/plugins/competitive.lua":
        return replace_once(text, '''    dependencies = { "MunifTanjim/nui.nvim" },
    cmd = "CompetiTest",
    opts = function() return require "configs.competitest" end,
''', '''    dependencies = {
      "MunifTanjim/nui.nvim",
      { dir = vim.fn.stdpath("config") .. "/local/cp-cache.nvim", name = "cp-cache.nvim", lazy = true },
    },
    ft = "cpp",
    cmd = { "CompetiTest", "CPCache" },
    opts = function() return require "configs.competitest" end,
    config = function(_, opts)
      require("cp_cache.adapter").setup_dependency(opts)
      require("cp_cache").setup()
    end,
''')
    if name == "lua/cp/init.lua":
        text = replace_once(text, '  vim.cmd "CompetiTest run"\n', '  require("cp_cache").run(buf, { compile = true })\n')
        return replace_once(text, '''  local testcases = {}
  if load_plugin("competitest.nvim", "competitest") then
    require("competitest.config").load_buffer_config(buf)
    testcases = require("competitest.testcases").buf_get_testcases(buf)
  end
''', '''  local cache = load_plugin("competitest.nvim", "cp_cache")
  if not cache then return end
  local testcases, cache_error = cache.get_testcases(buf)
  if not testcases then
    notify(cache_error, vim.log.levels.ERROR)
    return
  end
''')
    if name == "after/ftplugin/cpp.lua":
        return replace_once(text, 'map("<leader>c?", "<cmd>CPHelp<CR>", "open guide")',
                            'map("<leader>c?", "<cmd>CPHelp<CR>", "open guide")\n'
                            'map("<leader>cf", "<cmd>CPCache find<CR>", "find and share cached samples")\n'
                            'map("<leader>cI", "<cmd>CPCache info<CR>", "show current cached problem")')
    return text
