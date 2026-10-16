local root = vim.fn.stdpath("config")
for _, name in ipairs({"base46","ui","NvChad","plenary.nvim"}) do vim.opt.runtimepath:prepend(root .. "/.plugins/" .. name) end
vim.opt.runtimepath:prepend(root)
vim.g.base46_cache = vim.fn.stdpath("data") .. "/base46/"
require("base46").compile()
vim.cmd("qa!")
