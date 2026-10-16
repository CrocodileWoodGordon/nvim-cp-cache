local config = vim.fn.stdpath("config")
vim.opt.runtimepath:prepend(config .. "/.plugins/nui.nvim")
vim.opt.runtimepath:prepend(config .. "/.plugins/competitest.nvim")
vim.opt.runtimepath:prepend(assert(vim.env.CP_CACHE_PLUGIN))
vim.opt.runtimepath:append(config)
vim.o.swapfile, vim.o.backup, vim.o.writebackup, vim.o.undofile = false, false, false, false
vim.o.shadafile = "NONE"
-- Keep the real headless grid size; changing only options leaves an unresized grid.
vim.g.mapleader = " "
require("cp_cache.adapter").setup_dependency(require("configs.competitest"))
