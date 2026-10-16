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
    if name == "docs/competitive-programming.md":
        start, end = text.index("## 安装状态与首次启动"), text.index("## 五分钟体验")
        text = text[:start] + '''## 当前状态与环境前提

2026-10-16 已接入本地 **cp-cache.nvim**，集中保存样例并与 CompetiTest、
cp_tool.py、现有 GDB/DAP 共用。当前依赖已安装；未执行全量升级或系统包安装。
实测 Neovim 0.12.6、GDB 18.1、GCC 16.2.1、Python 3.14.8、clangd 23.1.1。

前提：已有配置内的 CompetiTest/nui、cp_tool.py 和 DAP 环境；GDB 需支持
原生 DAP 且允许 ptrace。浏览器导入需同机 Competitive Companion 与空闲端口 27121。
插件代码按 Neovim 0.10+ API 编写，但完整 NvChad 仅验收上述版本。

源码在 `~/.config/nvim/local/cp-cache.nvim/`，缓存默认
`~/.config/nvim/.cache/cp-cache/v1/`，重启后保留；不依赖 `/tmp`。
完整环境前提、命令、迁移与回退见 [插件 README](../local/cp-cache.nvim/README.md)，
验收矩阵见 [ACCEPTANCE.md](../local/cp-cache.nvim/ACCEPTANCE.md)。

C++ Treesitter parser 用于高亮和行末变量值；本轮没有安装或验收它。
Scopes/Stacks/Watches 不依赖 parser。可运行 `:CPHealth` 查看环境，不能将其当作调试验收。

已实测完整 NvChad/clangd、原快捷键、真实样例 UI/Telescope、三种编译模式、
本机 HTTP 接收、真实 PTY resize，以及 GDB 暂停、递归栈、locals、watch 和单步。
浏览器扩展按钮点击仍需本机人工验收；Rust 验证覆盖原键位。

''' + text[end:]
        text = replace_once(text, 'CompetiTest 使用端口 **27121**。', 'cp-cache 接收器使用端口 **27121**。')
        text = replace_once(text, '3. 样例会写入源码旁边的 `testcases/`。按 **空格 ct** 编译并比较全部样例。',
                            '3. 样例写入配置内的集中缓存，源码旁不生成样例或题目信息文件。看到“已保存”后按 **空格 ct** 比较。')
        text = replace_once(text, '已有样例遇到重复导入时，插件会询问替换方式。', '''已有样例遇到重复导入时，插件会询问“替换已接收（保留手工）/追加/取消”。
同题可关联多份解法，编辑共享样例时会显示题目。等待接收时切换窗口不会改变来源；
关闭或重命名发起操作的 buffer 后取消，不能误关联到新的焦点窗口。

## 缓存搜索、关联、迁移与清理

**空格 cf** / `:CPCache find` 按题号、标题、分组或 URL 搜索并关联当前源码；
**空格 cI** / `:CPCache info` 查看当前题目、源码路径、缓存文件和样例数。
源码改名或移动后，在新路径搜索原题重新关联。插件不按 `main.cpp` 这种 basename 猜题。
同一 main.cpp 改收新题会确认切换，旧题仍可搜索。

```vim
:CPCache migrate
:CPCache export files
:CPCache export msgpack
:CPCache forget
:CPCache remove
:CPCache reindex
```

migrate 只读复制当前源码的旧文本/msgpack，回读校验成功后关联；旧文件保留。
已有绑定（即使零样例）不会覆盖。forget 仅解绑；remove 显示关联数量并确认删除
整个题目，包括手工样例；源码、旧 testcases 和导出快照都保留。没有自动 TTL 删除。
损坏 JSON 报错并拒绝覆盖；只有索引可重建。缓存路径中的符号链接被拒绝。

托管 C++ 的旧 CompetiTest 命令均已接管。convert 改为缓存内格式导出，
files_to_singlefile 导出 msgpack，singlefile_to_files 导出文本，auto 切换格式。
权威 JSON 不变；非 C++ 保持原 CompetiTest 语义。''')
        text = replace_once(text, '| 空格 ca / ce / cx | 新增 / 编辑 / 删除样例 |',
                            '| 空格 ca / ce / cx | 新增 / 编辑 / 删除共享样例 |\n| 空格 cf / cI | 搜索重新关联 / 当前题目信息 |')
        start, end = text.index("样例文件名示例："), text.index("默认每例限时")
        text = text[:start] + '''样例保存在配置内缓存：

```text
源码目录/                 ~/.config/nvim/.cache/cp-cache/v1/
  A.cpp                     problems/<题目ID>.json
  B.cpp                     bindings/<源码路径hash>.json
                            index.json
                            exports/<题目ID>/
```

空输入、编号 0、CRLF 与末尾换行逐字节保留。空白输出保存时可选期待空输出或无标准答案。
编辑出现 revision 冲突时，重新加载或取消；不会覆盖其他实例的修改。

''' + text[end:]
        text = replace_once(text, '可在 `lua/configs/competitest.lua` 修改限时、比较方式和样例文件名。',
                            '可在 `lua/configs/competitest.lua` 修改限时和比较方式；样例文件名设置仅用于旧数据迁移/非 C++ 原存储。')
        text = replace_once(text, '普通样例模式的程序输出出现在 REPL，**REPL 的输入是 GDB 命令，不是程序的 cin**。',
                            '样例和测试共用 store；启动时在 `.runtime/inputs/` 创建输入快照，后续编辑不改变该会话。\n普通样例模式的程序输出出现在 REPL，**REPL 的输入是 GDB 命令，不是程序的 cin**。')
        text = replace_once(text, '''空格 da 的 Attach 需要系统允许 ptrace。此次执行沙箱禁止 ptrace，
因此无法在这里完成真实断点、单步和 UI 的端到端验证；不要为这个沙箱限制全局关闭系统安全设置。
在你本机正常终端中用上面的递归示例验收即可。''', '''空格 da 的 Attach 需要系统允许 ptrace。本轮真实 GDB/DAP 已通过缓存样例 0 验证：
main 暂停、递归断点、6 层调用栈、current=5/rest=0、watch 表达式结果 5 和单步。
证据在 `.verify/cp-cache/reports/gdb-evidence.json`。浏览器点击仍需人工验收。''')
        text = replace_once(text, '可重复运行编译/GDB 自检：', '旧环境编译/GDB 自检仍可运行（不代表 cp-cache 新验收）：')
        text = replace_once(text, '''原配置备份在 `backups/2026-10-14-before-cp/`。回退时恢复备份中的原文件，
再移走新增的 `lua/plugins/competitive.lua`、`plugin/cp.lua` 和 `after/ftplugin/cpp.lua` 即可停止加载新功能。
`.plugins/` 的副本可以保留；恢复原 `init.lua` 和 `configs/lazy.lua` 后会重新使用旧插件目录。''', '''本次 cp-cache 备份在 `backups/cp-cache-2026-10-16/`，只包含本次四个入口/教程文件。
停止接收/调试并退出 Neovim，在开发仓库执行 `python3 tools/verify.py rollback --check`，
再执行 `python3 tools/verify.py rollback`。工具校验备份和部署哈希，拒绝覆盖后续用户修改。
缓存、旧样例、插件副本和 GDB/编译器设施保留。不要恢复 2026-10-14-before-cp 做本次回退。
手动回退也只恢复本次备份中的同名四个文件。''')
        return text
    return text
