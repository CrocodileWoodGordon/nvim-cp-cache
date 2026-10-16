local config = vim.fn.stdpath("config")
vim.o.swapfile, vim.o.backup, vim.o.writebackup, vim.o.undofile = false, false, false, false
vim.o.shadafile = "NONE"
vim.opt.runtimepath:prepend(config .. "/.plugins/lazy.nvim")
vim.opt.runtimepath:prepend(assert(vim.env.CP_CACHE_PLUGIN))
require("lazy").setup({
  { "xeluxee/competitest.nvim", cmd = "CompetiTest", dependencies = { "MunifTanjim/nui.nvim" },
    config = function()
      local a = require("cp_cache.adapter")
      a.setup_dependency({})
      a.install_dispatch(function() vim.g.cp_dispatch_calls = (vim.g.cp_dispatch_calls or 0) + 1; return true end)
    end },
}, { root = config .. "/.plugins", lockfile = config .. "/lazy-lock.json", install = { missing = false },
  checker = { enabled = false }, change_detection = { enabled = false } })
