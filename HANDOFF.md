# 实现交接：当前环境与证据

## 当前状态

截至 2026-10-16，本任务轮次只做了只读调查并生成 `/tmp/nvim-cp-cache/` 中的任务文档。**缓存插件还没有编写，当前样例仍保存在源码旁的 `testcases/`。** 不要把文档中的未来命令当成已经安装的功能。

用户原目标是保留已有功能，增加 VSCode/CPH 风格的 C++ 调试与样例工作流。后续要求样例不进源码目录；如需自写插件，先确定目标、技术栈、规划和交接，留给其他 AI 实现。用户进一步指定 AGENTS 等文档放 `/tmp`。

已选择持久题目缓存方案，暂名 cp-cache.nvim。实施路径与目标见 README；详细契约见 DESIGN。

## 真实环境

- 用户目录 `/home/gordon`，Arch Linux，zsh。
- 配置 `/home/gordon/.config/nvim`，实际是 **NvChad + lazy.nvim**，不是 LazyVim。
- 上轮检测：Neovim 0.12.6、GDB 18.1、GCC 16.2.1，已有 Python、clangd。实施时再检查需要的可执行文件。
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

| 文件 | 现有职责与预计改动 |
| --- | --- |
| `lua/plugins/competitive.lua` | lazy 插件定义、DAP 全局键位；新增本地 cp-cache 依赖和 setup 顺序 |
| `lua/configs/competitest.lua` | 编译/运行调用 Python 工具；当前 `testcases_directory="testcases"`；保留运行配置 |
| `lua/cp/init.lua` | build/test/debug/run；debug 目前用 `buf_get_testcases` 取样例；改成统一缓存 API |
| `plugin/cp.lua` | CPHelp、CPHealth、CPDebug、CPBuild、CPRun、CPTest 命令；保持可用 |
| `after/ftplugin/cpp.lua` | C++ buffer 键位；接入缓存并加搜索键，不覆盖 Rust 的 buffer 映射 |
| `lua/configs/dap.lua`、`lua/cp/debug.lua` | 现有 GDB 启动和辅助查询；原则上无需改动 |
| `scripts/cp_tool.py` | GNU++20、release/debug/sanitize、源码路径哈希构建目录；直接复用 |
| `scripts/check_cp.py` | 旧编译/GDB 验证，读取示例的固定 `testcases/main.N.in/out` 路径 |
| `.verify/nvim-smoke.lua` | 旧完整配置烟雾验证；注意隔离 XDG 路径后再运行 |
| `examples/cp-demo/main.cpp` | 递归求和例子；两个样例输出分别为 15、6 |
| `examples/cp-demo/testcases/` | 已有样例，迁移时只复制，保留原文件供旧测试/回退使用 |
| `templates/contest.cpp` | 新题模板，继续使用 |
| `docs/competitive-programming.md` | 现有中文教程；接入完成后更新存储、键位与安装状态 |

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

这些模块导出接口需要通过 P0 用真实版本验证；它们不等价于上游稳定 API 承诺。

## 原有操作必须保留

空格是 leader。`ct/cs` 分别测试 release/sanitize；`cr` 接收当前样例；`cP/cC` 接收新题/比赛；`ca/ce/cx` 增删改；`cu` 重新打开结果；`cd` 开始调试；`cb` 编译 debug；`cR` 交互运行；`c?` 打开帮助。

F5/F9/F10/F11 与 `<leader>d…` 的调试键继续工作。重点保留 NvChad 的 `<leader>ds`、`ch`、`fm`，以及 Rust 的 buffer 键位。

当前 `M.debug` 的输入选项包括样例、任意输入文件、交互终端、EOF。它会按数字排序样例，并生成独立输入快照；换存储不能删除这些分支。`CPDebug 0` 必须仍能选到编号 0。

## 旧验证的边界

`.verify/verification-results.json` 是前一轮结果，不能当成本插件的新测试：旧编译测试通过，GDB DAP 握手/断点登记通过，真实断点暂停被 sandbox 的 ptrace 限制阻挡；其中“插件未安装”项现已过时。

先前 shell 网络受限，不代表用户当前终端也不能联网。优先利用现有依赖，避免无关下载。真实 GDB 调试被限制时，仍能验证传入 DAP 的缓存样例快照，再把断点/栈/变量列为本机人工检查项。

完整 NvChad 的无界面测试可能需要触发 UIEnter 才会加载 LSP，空 buffer 还可能触发 dashboard。先用 `-u NONE -i NONE` 加载指定 runtimepath 测最小集成，再用具名 C++ 测完整配置。

## 下一步

从 PLAN 的 P0 开始。实现前给相关配置建立本轮备份；不要恢复旧 `backups/2026-10-14-before-cp/`，那会撤掉已完成的调试配置。完成集成后再更新教程中失效的安装状态和样例位置说明。
