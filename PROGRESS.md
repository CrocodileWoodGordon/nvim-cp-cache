# 开发进度

当前状态：P0–P5 实现与核心验收完成；浏览器按钮点击留人工项。以下按实际开发顺序保留记录，最终结果见末尾与 ACCEPTANCE.md。

## 2026-10-16：设计交接完成

- 完成：读取当前 Neovim 配置和已安装 CompetiTest 源码，核对官方文档与备选插件，确定持久集中缓存方案。
- 交付：README.md、AGENTS.md、HANDOFF.md、DESIGN.md、PLAN.md。
- 代码状态：cp-cache.nvim 尚未实现；插件源码目录尚未创建；现有 Neovim 配置没有在本轮改动；样例仍使用原位置。
- 验证范围：本任务包的文件存在性、文档互链、JSON 示例结构、本机路径与锁版本对应关系。不是功能验收。
- 阶段状态：P0、P1、P2、P3、P4、P5 均未开始。
- 下一步：按 PLAN 的 P0，创建隔离测试并验证真实 runner/editor 与命令兼容入口。
- 已知环境限制：前轮真实 GDB 执行受 ptrace 限制；安装状态已变化，前轮报告中“六个插件缺失”不再有效。

后续实现者在下方按阶段追加实际改动与实际测试结果。

## 2026-10-16：P0 完成

- 用户最新路径要求：开发在本仓库，测试副本在 `~/.config/nvim/local/cp-cache.nvim`，生成数据在 `.verify/cp-cache/`；不依赖 `/tmp`。
- 文件：`tools/verify.py`、`tests/{minimal_init,helpers,probe,lazy_init,lazy_probe}.lua`、`lua/cp_cache/adapter.lua`。
- 备份：`~/.config/nvim/backups/cp-cache-2026-10-16/manifest.json`，含四个拟改配置入口的 SHA256；尚未切换正式配置。
- 实际命令：`python3 tools/verify.py probe`、`python3 tools/verify.py lazy_probe`，均 PASS。
- 真实 CompetiTest：编号 0/2 两个样例编译比较通过；editor 保存逐字节返回中文/CRLF/末尾换行，取消不回调；runner 关闭/重开/resize/delete 通过。
- 实际 lazy.nvim 首次命令加载与接管、重复 setup、命令补全、接管后 `-bar` 通过。lazy 的首次占位命令本身没有 `-bar`，测试分别验证首次加载与接管后的分隔符；P4 通过 C++ FileType 预加载消除此窗口。
- 兼容性发现：上游 kill_all 会继续启动排队样例；cleanup 先终止队列再 kill，并调用真实 UI `delete()`。
- 下一步：P1 身份、锁/revision、原子存储与关联；buffer unload 的自动清理在 P2 接入。

## 2026-10-16：P1 完成

- 文件：`identity.lua`、`store.lua`、`tests/{store,worker,run}.lua`。
- 实际命令：`python3 tools/verify.py run`，PASS；内含两个真实独立 Neovim 进程竞争同一 revision，恰好一个写入成功，另一个得到冲突/忙锁。
- 已验证：CF URL 合并/Gym 分离/相似恶意 host、通用 URL query 保留；同名源码隔离、软链规范路径、多个源码共享题目；编号 0、空输入、缺省与空 output、中文/CRLF/末尾换行；跨进程重开持久化。
- 已验证：独占锁与活 PID 拒绝恢复、死 PID 显式恢复；损坏/未知 schema 不能覆盖；索引损坏/丢失重建；缓存软链拒绝读取/写入/删除；空题保留关联；重新关联不删旧题。
- 原子写采用同目录独占临时文件、完整写入/fsync/close/rename；每题/关联写操作均加锁，忙时立即提示重试，不阻塞 UI。
- 下一步：P2 运行、编辑、搜索、只读迁移、缓存导出及命令/API。配置正式入口尚未修改。

## 2026-10-16：P2 完成

- 文件：`init.lua`、`adapter.lua`、`picker.lua`、`migrate.lua`、`tests/workflow.lua`。
- 实际命令：`python3 tools/verify.py run`、扩展后的 `python3 tools/verify.py probe`，PASS。
- 真实 UI 验证：新增/编辑/取消/冲突保存/删除最后一例；共享编辑；选择空输出或无答案；结果面板 R 从 store 取最新样例，Ctrl-R 重载全部；diff、输入查看器、关闭重开、resize；卸载源 buffer 后关闭编辑窗口。
- release/sanitize 编译比较通过，特殊源码路径包含空格、中文和单引号。源码目录前后完整快照相同。
- 文本与 msgpack 迁移均逐字节复制，旧文件快照不变；重复迁移拒绝覆盖；缓存内导出保留编号 0、空/缺省 output；`vim.ui.select` 后备搜索与重命名后重新关联通过。Telescope 实际选择在 P4 完整配置验证。
- 测试发现并修正：不能只设置 headless `lines/columns` 而不调整真实网格，否则 Neovim 0.12.6 在 NUI redraw 中崩溃（GDB 栈为 grid_clear_line/update_screen）。测试保留真实尺寸；生产标题另按显示宽度截断。BufUnload 中的窗口清理安排到下一次主循环。
- 下一步：P3 实现真实 HTTP Companion 接收；正式配置仍未切换。P2 命令/API 已预留接收入口，接收模块在 P3 交付。

## 2026-10-16：P3 完成

- 文件：`receiver.lua`、`tests/receiver.lua`、`tests/http_client.py`；关联写入增加 compare-and-set，等待用户选择时不会覆盖并发变更的 binding。
- 实际命令：`python3 tools/verify.py receiver`，PASS。全部请求通过真实 `127.0.0.1` TCP socket 和 Python 标准库发送，没有仅调用 ingest 来替代 HTTP。
- 已验证：每 7 字节分片（含中文 UTF-8 被拆分）、无末尾换行 JSON、OPTIONS、错误 JSON/字段、GET、重复 Content-Length、16 KiB 头/8 MiB 体限制、空闲超时；错误请求后服务继续可用。
- 已验证：切换 buffer 后仍绑定原源码；关闭源 buffer 后取消；换题确认取消/确认；旧题仍在库中；替换 received 保留 manual；相同 payload 不增加 revision/样例。
- 已验证：端口占用错误、重复 start、幂等 stop、stop 后启动、待处理路径回调停止后不再写文件；新题函数路径、已有源码保持内容并确认、模板原样复制/展开；两个交错比赛去重、残缺批次超时后重发恢复。
- 对创建目录做完整快照，只有选择创建的 `.cpp`；当前源码目录快照无变化。
- 测试细节：HTTP 客户端使用异步完成回调与完整主循环；`vim.system():wait()` 仅处理 fast events，会阻止 schedule 中的实际 UI/保存回调，不能用于该测试。
- 浏览器 Competitive Companion 按钮点击未验证，留 P5 人工验收；协议和本机网络已实测。
- 下一步：P4 接入本机 NvChad、原 CPTest/CPDebug 和 CPP 键位，迁移 demo，然后完整配置验证。

## 2026-10-16：P4 完成

- 文件：`integration/{changes.py,nvim.patch}`、`tests/{theme,full,debug_inputs,gdb,migrate_demo}.lua`、`tools/verify.py`。
- 配置修改仅三处：CompetiTest lazy spec 依赖本地插件并在 C++ FileType 预加载；`cp.init` 的 CPTest/CPDebug 取样例入口；CPP 新增 `cf/cI`。原编译器工具、GDB adapter/debug 辅助模块、Rust/NvChad 配置未编辑。
- 接入前已重读所有目标文件；工具逐文件核对备份 SHA256，防止覆盖并发修改。正式副本在 `~/.config/nvim/local/cp-cache.nvim`，正式缓存 `.cache/cp-cache/v1`，无 `/tmp` 依赖。
- 实际命令：`python3 tools/verify.py baseline`、`install`、`migrate_demo`、`full`、`gdb`，PASS。
- 完整 NvChad：clangd 初始化、原 CPP/Rust/F9/ds/ch/fm 键位基线一致；CPTest release/sanitize 输出 15/6；真实 Telescope 选择关联；原 CompetiTest editor/convert 和 `-bar`；源码目录快照无新增非源码文件。
- A17 为启动参数捕获测试：编号 0/2、更新字节、快照隔离、文件输入/交互 PTY/EOF、损坏缓存中止，PASS；明确不是实际 GDB 的证据。
- A18 是实际 GDB/DAP：从缓存样例 0 编译启动，main 暂停，递归断点，6 层调用栈，locals current=5/rest=0，watch current+rest=5，单步暂停，正常终止，PASS。证据 `.verify/cp-cache/reports/gdb-evidence.json`。本轮升级权限后的进程允许 ptrace，旧交接中的限制没有重复出现。
- 环境：Neovim 0.12.6、GDB 18.1、GCC 16.2.1、Python 3.14.8、clangd 23.1.1；未下载/升级任何依赖。Rust 测试覆盖原键位，不宣称独立无 Cargo fixture 的 rust-analyzer 初始化成功。
- 下一步：P5 超时/kill/编译失败/清理边界验收、中文 README/帮助、教程与回退，最终统一检查。

## 2026-10-16：P5 边界验收（进行中）

- `python3 tools/verify.py acceptance`、`python3 tools/verify.py resize`：PASS。
- 修复首次空 buffer 复用的真实竞态：BufUnload 立即捕获旧 runner/editor 对象，终止旧进程；窗口删除安排到主循环。不能在延迟回调里仅按 buffer 编号查 runner，那可能已经属于新文件。
- 已验证 WA、编译错误阻止旧 binary 运行、150ms 超时、Ctrl-K 不启动排队样例、Ctrl-R 重跑、源 buffer 卸载无遗留进程/UI；删除共享题目显示两份关联并确认；真实目录权限导致写入失败时原 JSON 字节不变；非 C++ 原命令仍使用其旧存储。
- PTY 驱动真实 Neovim TUI，通过 SIGWINCH 将 runner 改到 110×38、editor 改到 100×34；窗口有效，编辑内容和保存回调保留。不是只调用 resize 方法或手动修改 options。
- 增加 binding 死锁的显式 PID 恢复；删除缓存关联不再重新解析已被用户替换/重命名的源码路径。
- P4 完整套件在复跑时发现测试快照只从 after 排除 `renamed.cpp`，而上次测试已创建该文件；现已同时从 before/after 排除明确创建的源码。此前功能断言与真实 GDB 均已通过，最终 full 套件待 P5 统一复跑确认。
- 剩余：完整套件、补充接收模式覆盖、用户文档/帮助、回退和最终验收矩阵。

## 2026-10-16：P5 接收与 I/O 最终检查

- 增加短读/短写的明确错误，避免对变化中的文件假报读取成功；源码创建的写入错误带目标路径。锁写入检查完整字节数。
- 接收器补验收期间真实重命名，确认取消而非误关联；独立 Neovim 带活动监听退出后，同端口可立即重新监听。
- `python3 tools/verify.py run`：全部 P1/P2/P3/P5 套件 PASS，覆盖 problem/contest/persistently 的完整题目和仅样例分支；批次测试超时留足调度余量。
- 最终核心文件再次部署到配置内运行副本；真实 GDB 的最终生命周期复核也 PASS。

## 2026-10-16：P5 面板边界复核

- 真实进程验证停止 Compile 时也停止待运行队列：上游回调只看 exit code，信号杀死进程可能是 code=0/signal!=0，adapter 在停止编译前阻断队列，避免运行旧 binary。
- BufFilePost 与 BufUnload 共用捕获旧对象的清理；源码改名后不保留旧路径的 runner/编辑器，重新关联通过 find 完成。
- `python3 tools/verify.py acceptance`：PASS，包含实际编译停止、源码改名清理和既有进程边界项。
- `python3 tools/verify.py store`：PASS，额外核对源码软链与 `..` 的组合路径，存在文件及未创建文件均与物理父目录一致。
- 原命令的未命名 CPP 分支现在明确报错并结束分发，不会退回旧存储；在隔离空目录实测无新增文件。非 CPP 原编辑保存仍正常。
- `python3 tools/verify.py receiver`：增加真实索引目录 EACCES 场景，题目/关联已落盘时只报告明确的部分失败，不再追加整体“已保存”提示；其余真实 HTTP 场景全部 PASS。
