# 实现交接：当前环境与证据

## 当前状态

截至 2026-10-16，P0–P5 的插件实现、NvChad 接入和核心验收已完成，并在当前仓库分步提交。
开发目录 `/home/gordon/Coding/nvim-cp-cache/`；运行副本 `~/.config/nvim/local/cp-cache.nvim/`；
正式缓存 `~/.config/nvim/.cache/cp-cache/v1/`。demo 旧样例已只读复制到缓存，旧文件保留。
最新结果以 ACCEPTANCE.md / PROGRESS.md 为准；下文调查结论保留供维护适配层使用。

用户原目标是保留已有功能，增加 VSCode/CPH 风格的 C++ 调试与样例工作流。后续要求样例不进源码目录；如需自写插件，先确定目标、技术栈、规划和交接，留给其他 AI 实现。用户进一步指定 AGENTS 等文档放 `/tmp`。

已实现持久题目缓存 cp-cache.nvim。使用与环境前提见 README；详细契约见 DESIGN。

## 真实环境

- 用户目录 `/home/gordon`，Arch Linux，zsh。
- 配置 `/home/gordon/.config/nvim`，实际是 **NvChad + lazy.nvim**，不是 LazyVim。
- 本轮核对：Neovim 0.12.6、GDB 18.1、GCC 16.2.1、Python 3.14.8、clangd 23.1.1。
- 插件根目录已经是 `.config/nvim/.plugins/`，不是默认 data/lazy；旧插件与原安装目录并存，不要清理旧目录。
- `lazy-lock.json` 当前包含下列依赖，目录实际存在。上轮文档“六个插件尚未安装”的段落已经过时。
- `.treesitter/parser/cpp.so` 在本轮检查时不存在；不要因此重装整套插件。行末变量渲染的 parser 状态应单独核验。

| 插件 | 当前 lock commit |
| --- | --- |
| competitest.nvim | `b42c06ca308906f07912ba9aff015ac2c0831f85` |
| nui.nvim | `10fc361835c856ba4233ef5ea135b919bf3dce97` |
| nvim-dap | `cfa2d58f4537aca6ca83e2de1a0d9f1491121264` |
| nvim-dap-ui | `cc9dd33aade7f20bae414d0cba163bc60d4d4b43` |
| nvim-nio | `edcc181a875301dd21840189aa2f2f9ad69fc172` |
| nvim-dap-virtual-text | `fbdb48c2ed45f4a8293d0d483f7730d24467ccb6` |

## 必读的本机文件

以下路径均相对于 `/home/gordon/.config/nvim/`。

| 文件 | 现有职责与本轮改动 |
| --- | --- |
| `lua/plugins/competitive.lua` | 已新增本地 cp-cache 依赖、CPP FileType 触发和 setup 顺序；原 DAP 全局键位保留 |
| `lua/configs/competitest.lua` | 编译/运行调用 Python 工具；当前 `testcases_directory="testcases"`；保留运行配置 |
| `lua/cp/init.lua` | CPTest/CPDebug 已改成统一 cp_cache；build/run 与 GDB 其他输入分支保留 |
| `plugin/cp.lua` | CPHelp、CPHealth、CPDebug、CPBuild、CPRun、CPTest 命令；保持可用 |
| `after/ftplugin/cpp.lua` | 已保留原 CPP 映射并加 cf/cI；Rust 映射基线验证一致 |
| `lua/configs/dap.lua`、`lua/cp/debug.lua` | 现有 GDB 启动和辅助查询；原则上无需改动 |
| `scripts/cp_tool.py` | GNU++20、release/debug/sanitize、源码路径哈希构建目录；直接复用 |
| `scripts/check_cp.py` | 旧编译/GDB 验证，读取示例的固定 `testcases/main.N.in/out` 路径 |
| `.verify/nvim-smoke.lua` | 旧完整配置烟雾验证；注意隔离 XDG 路径后再运行 |
| `examples/cp-demo/main.cpp` | 递归求和例子；两个样例输出分别为 15、6 |
| `examples/cp-demo/testcases/` | 已有样例，迁移时只复制，保留原文件供旧测试/回退使用 |
| `templates/contest.cpp` | 新题模板，继续使用 |
| `docs/competitive-programming.md` | 已更新中文教程：集中缓存、键位、环境前提、迁移/回退与实际验收 |

编译产物在 `.build/<源码路径哈希>/`。调试输入快照在 `.runtime/inputs/`；这些都已经不在用户源码目录内，不必重设计。

## CompetiTest 调查结论

检查了实际安装的模块，不仅是 README：

1. `lua/competitest/testcases.lua` 的私有 `buf_get_testcases_path` 直接拼接“源码父目录 + testcases_directory”。绝对路径作为配置值并不会替换父目录。
2. `config.lua` 中 `testcases_directory` 是相对目录字符串，不接受按题目计算路径的函数。每次命令会重载 buffer config，事先改一次 `buffer_configs` 不能稳定接管。
3. `utils.file_format_modifiers` 虽然导出了函数型替换表，但用它改单文件路径仍需单独实现索引，且不能自动覆盖转换、I/O 文件扫描等路径。不要用固定数量 `../` 逃到根目录。
4. 仅拦截 `buf_write_testcases` 不够：编辑、删除会直接调 `single_file.buf_write` / `io_files.buf_write_pair`；接收新题/比赛会调更低层的 `single_file.write` / `io_files.write_eval_format_string`。
5. `receive.lua` 的接收类和 storage_utils 都是私有局部变量；只导出 start/stop/status。`receive testcases` 丢弃任务标题和 URL，只将 tests 交给存储。不要用 `debug.getupvalue` 从闭包偷取内部接口。
6. `commands.lua` 保有 runner 表，现有 `CompetiTest.setup()` 的调整大小逻辑会遍历它。自建 adapter runner 必须纳入此表或提供等价 resize/cleanup，防止面板残留。

在已安装版本中可用于窄适配层的导出入口：

- `require('competitest.config').load_buffer_config(bufnr)`：给 runner/editor 加载运行和界面选项。
- `require('competitest.runner'):new(bufnr)`：构造 runner；`run_testcases(tctbl, compile)` 接收内存数字键样例表，不要求样例在源码目录。
- runner 的 `kill_all_processes()`、`set_restore_winid(winid)`、`show_ui()`、`resize_ui()`。
- `require('competitest.widgets').editor(bufnr, tcnum, input, output, callback, restore_winid)`：保存时交回 `{input, output}`，适合写入 cache store。
- 同模块 `picker(bufnr, tctbl, title, callback, restore_winid)`。
- `require('competitest.commands').command(arguments)`：可保留为非托管语言的原命令入口。

这些模块导出接口已通过 P0 与后续真实 UI/TUI 验证；它们不等价于上游稳定 API 承诺。

## 原有操作必须保留

空格是 leader。`ct/cs` 分别测试 release/sanitize；`cr` 接收当前样例；`cP/cC` 接收新题/比赛；`ca/ce/cx` 增删改；`cu` 重新打开结果；`cd` 开始调试；`cb` 编译 debug；`cR` 交互运行；`c?` 打开帮助。

F5/F9/F10/F11 与 `<leader>d…` 的调试键继续工作。重点保留 NvChad 的 `<leader>ds`、`ch`、`fm`，以及 Rust 的 buffer 键位。

当前 `M.debug` 的输入选项包括样例、任意输入文件、交互终端、EOF。它会按数字排序样例，并生成独立输入快照；换存储不能删除这些分支。`CPDebug 0` 必须仍能选到编号 0。

## 旧验证的边界

`.verify/verification-results.json` 是前一轮结果，不能当成本插件的新测试：旧编译测试通过，GDB DAP 握手/断点登记通过，真实断点暂停被 sandbox 的 ptrace 限制阻挡；其中“插件未安装”项现已过时。

先前 ptrace 限制在本轮批准的测试进程中未重现。真实 GDB/DAP 已通过缓存样例 0 的
main 暂停、递归断点、6 层栈、locals、watch 和单步验证；A17 的参数捕获仍单独标记。
本轮未安装/升级依赖。浏览器按钮点击仍没有可用的交互入口，留人工验收。

完整 NvChad 的无界面测试可能需要触发 UIEnter 才会加载 LSP，空 buffer 还可能触发 dashboard。先用 `-u NONE -i NONE` 加载指定 runtimepath 测最小集成，再用具名 C++ 测完整配置。

## 下一步

维护时先读 README、ACCEPTANCE 和 PROGRESS，再改代码。本次配置备份在
`~/.config/nvim/backups/cp-cache-2026-10-16/`；`tools/verify.py install/rollback` 均检查哈希，
不覆盖用户并发修改。不要恢复 `2026-10-14-before-cp`，那会撤掉现有 GDB 环境。

剩余人工项是实际浏览器扩展按钮导入。其余核心项已有真实依赖、真实 HTTP、真实 TUI resize
和真实 GDB 证据。C++ Treesitter 行末变量渲染、Cargo 项目内 Rust LSP 不属于本轮已验证范围。
