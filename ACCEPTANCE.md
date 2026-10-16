# cp-cache.nvim 首版验收

日期：2026-10-16。开发在本仓库，运行副本在 `~/.config/nvim/local/cp-cache.nvim/`。
核心项 PASS；当前无已知未修复 FAIL。浏览器人工操作单独列为 BLOCKED，不将协议 fixture 当作按钮点击证据。

## 环境与命令

Arch Linux、Neovim 0.12.6/LuaJIT、NvChad v2.5、lazy.nvim、GDB 18.1、GCC 16.2.1、Python 3.14.8、clangd 23.1.1。
CompetiTest `b42c06ca308906f07912ba9aff015ac2c0831f85`，nui `10fc361835c856ba4233ef5ea135b919bf3dce97`，
Telescope `427b576c16792edad01a92b89721d923c19ad60f`；未升级依赖。

在本仓库执行：

```sh
python3 tools/verify.py probe
python3 tools/verify.py lazy_probe
python3 tools/verify.py run
python3 tools/verify.py resize
python3 tools/verify.py full
python3 tools/verify.py gdb
python3 tools/verify.py doc_check
python3 tools/verify.py rollback --check
```

验证目录为 `~/.config/nvim/.verify/cp-cache/`。XDG_DATA_HOME、XDG_STATE_HOME、XDG_CACHE_HOME、TMPDIR、NVIM_LOG_FILE 均隔离在其下；正常读取既有配置和插件，不引导 lazy 下载。
原 cp_tool.py 构建产物仍在配置内 `.build/`，CPDebug 快照仍在 `.runtime/inputs/`。测试 C++ 源码和接收目标均在 `.verify/cp-cache/fixtures/`；demo 迁移只读原数据。

日志：`reports/{probe,lazy_probe,run,resize,full,gdb,doc_check}.log`；真实 TUI 原始记录 `reports/resize-tui.log`；GDB 数据证据 `reports/gdb-evidence.json`；原键位基线 `reports/mappings-baseline.json`。

## 验收矩阵

| 编号 | 状态 | 实际覆盖与证据 |
| --- | --- | --- |
| A01 | PASS | store/worker 独立 Neovim 重开持久化；workflow 首次手工样例、绑定和完整目录快照 |
| A02 | PASS | 不同目录同名 main.cpp 隔离，多源码显式共享；shared editor 修改两边可见 |
| A03 | PASS | contest/problemset 同 ID，Gym 独立，相似恶意 host 走完整 URL hash，query 保留 |
| A04 | PASS | HTTP 题 A→B 取消/确认，A 数据仍在库；实际 Telescope 与后备选择关联旧题 |
| A05 | PASS | 编号 0、空输入、空/缺省 output、中文、CRLF、末尾换行；真实 editor 回调和 mpack/files 导出字节校验 |
| A06 | PASS | 真实新增/编辑/取消/冲突/删除最后一例，空题绑定保留，不重新迁移 |
| A07 | PASS | 完整 CPTest release/sanitize 的 demo 15/6；错误程序 WA；编译失败或停止编译时旧 binary 不启动 |
| A08 | PASS | 150ms 超时，Ctrl-K 阻止排队样例，Ctrl-R 重跑；关闭/重开/卸载无遗留进程；真实 TUI resize |
| A09 | PASS | 实际 TCP 每 7 字节分片、UTF-8 中文 Content-Length、无末尾换行 JSON；错误 JSON/字段/头和超限响应后仍可用 |
| A10 | PASS | 实际端口占用、重复 start、幂等 stop、stop 后重启；VimLeavePre 关闭服务和 runner |
| A11 | PASS | 接收期间换 buffer 保持原目标，关闭原 buffer 后取消；等待路径选择时 stop 使回调失效 |
| A12 | PASS | 两个交错比赛 batch、重复 POST 不重复计数，残缺批次超时后重发恢复 |
| A13 | PASS | 实际 HTTP testcases/problem/contest/persistently；持续模式样例/完整题目；函数和字符串路径、原样/展开模板、已有源码确认保留 |
| A14 | PASS | 文本与 msgpack 只读迁移、逐字节回读、重复迁移拒绝覆盖；旧文件完整快照不变；正式 demo 同样校验 |
| A15 | PASS | 两独立 Neovim 写同 revision，恰好一个成功；损坏 JSON/未知 schema 拒绝覆盖；索引丢失/损坏重建；真实 EACCES 保留旧字节；接收索引失败明确报告部分保存 |
| A16 | PASS | 编译路径含空格/中文/单引号；源码与父目录软链规范化；真实 Telescope 给 renamed.cpp 重新关联 |
| A17 | PASS（启动捕获） | 原 CPDebug 0/2、编辑后字节、不可变快照、输入文件、交互 PTY、EOF；损坏缓存中止。此项截获 dap.run，不能当作真实断点证据 |
| A18 | PASS（真实 GDB） | 真正 nvim-dap/GDB 编译启动缓存样例 0，main 暂停，递归断点，6 层栈，current=5/rest=0，watch current+rest=5，单步并终止 |
| A19 | PASS | 实际 lazy 首次命令与重复 setup，托管 CompetiTest run/edit/convert，补全和接管后 -bar；未命名 CPP 不落入旧存储；非 CPP 真实原编辑保存仍走旧存储 |
| A20 | PASS（声明范围） | 完整 NvChad 的 ds/ch/fm/CPP/Rust/F9 基线一致，新 cf/cI 不泄漏 Rust；clangd 初始化。未声称 Cargo 项目 Rust LSP 通过 |
| A21 | PASS | cache 内导出、解绑、共享题两关联确认删除；源码/旧样例保留；根/子路径软链拒绝；活 PID 拒绝解锁、死 PID 显式恢复 |
| A22 | PASS | 源码目录完整 before/after 快照，仅排除明确创建/保存的源码；正式配置只依赖配置内副本；四文件备份/部署 SHA256 校验和回退预检 |

## 人工项与限制

| 项目 | 状态 | 原因与本机复现 |
| --- | --- | --- |
| Competitive Companion 实际按钮点击 | BLOCKED（待人工） | 代理没有浏览器扩展交互入口。重启 Neovim 打开 A.cpp，空格 cr；浏览器打开 Codeforces 题，扩展 Custom ports 加 27121，点击 +；看到已保存后空格 ct，并用 cI 确认 URL/题目 |
| 外网题面获取 | BLOCKED（待人工） | 插件依靠浏览器扩展解析，不提供抓取器；本轮使用协议 fixture 和本机真实 HTTP，未把它记为外网成功 |
| 源码行末变量渲染 | 未验收 | C++ Treesitter parser 本轮未安装/升级。GDB Scopes/Stacks/Watches 已真实验收；parser 的安装与显示由现有环境单独管理 |

当前环境允许本轮 GDB 测试进程 ptrace；旧交接里的 ptrace BLOCKED 不再代表本轮结果。
原配置启动 `/usr/lib/rustup/bin/rust-analyzer` 时，当前 stable 工具链返回 `Unknown binary 'rust-analyzer'`，接入前基线也如此。本轮只核对原 Rust 映射，不将其记为 Rust 项目 LSP 通过，也未修改 Rust 工具链。

## 已修复的验收发现

- headless 不能只设置 lines/columns 而不调整真实屏幕网格；这曾导致 Neovim grid_clear_line 崩溃。最小测试保留真实尺寸，调整尺寸改用真实 PTY/SIGWINCH。
- CompetiTest kill_all 原来会由退出回调启动排队样例；adapter 先终止队列。
- BufUnload 清理必须捕获旧 runner/editor 对象，不能延迟按复用的 buffer 编号查找；NUI 窗口删除要放到主循环。
- 完整套件重复运行时，明确创建的 renamed.cpp 要从 before 和 after 同时排除；其他目录项仍逐一比较。
- 损坏缓存是注入的预期错误，日志保留错误提示；测试确认中止启动后清除预期 errmsg，再检查其他错误。

回退详见 README；`rollback --check` 校验所有备份/部署哈希，预检不修改入口。未用实际恢复用户配置来代替预检，也没有删除缓存或旧样例。
