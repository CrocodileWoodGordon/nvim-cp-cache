# 开发进度

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
