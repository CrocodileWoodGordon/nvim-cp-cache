# cp-cache.nvim 开发任务包

状态：**设计与交接已准备，插件尚未实现，现有 Neovim 配置尚未切换到缓存。**

设计日期：2026-10-16。请先读 [AGENTS.md](AGENTS.md)，再读 [HANDOFF.md](HANDOFF.md)、[DESIGN.md](DESIGN.md)、[PLAN.md](PLAN.md)。

## 已确定的目标

为当前 NvChad + lazy.nvim 的 C++ 竞赛环境增加集中样例库：

- 样例、题目元数据、源码关联和搜索索引均放在一个缓存根目录；源码目录不生成 `testcases/`、`.cph` 或题目信息文件。
- 从 Competitive Companion 接收 Codeforces 样例；支持当前源码、新题、整场比赛三种工作流。
- 按题号、标题、URL 搜索并把已有题目的样例关联到当前源码；同一道题可以关联多份解法。
- 保留一键编译比较、样例增删改、差异查看、release/sanitize 模式和现有 GDB 功能。
- 测试与调试读取同一份样例；GDB 启动时生成输入快照，后续编辑样例不影响正在进行的会话。

用户接受“临时样例”或“带索引的缓存”二者之一。本方案选择**持久缓存**；临时模式不属于首版必做项。

## 已确定的技术栈

| 部分 | 选择 |
| --- | --- |
| 插件语言 | Lua，兼容 Neovim LuaJIT；最低 Neovim 0.10，主要验收本机 0.12.6 |
| 异步、文件、网络 | Neovim 自带 `vim.uv`、`vim.schedule`、`vim.system` |
| 存储 | 版本化 JSON；每题一个权威数据文件；独立源码关联文件；可重建索引 |
| 运行和结果 UI | 复用已安装的 CompetiTest 与 nui.nvim |
| 样例编辑 UI | 复用 CompetiTest editor/picker，通过回调写入缓存 |
| 搜索 | 已有 Telescope；缺失时退回 `vim.ui.select` |
| 题面解析 | 用户浏览器的 Competitive Companion；插件仅接收 JSON |
| C++ 编译 | 沿用现有 `scripts/cp_tool.py` |
| 调试 | 沿用 nvim-dap、dap-ui、GDB 原生 DAP |
| 测试 | 无界面 Neovim + Lua 断言；Python 标准库可用于 HTTP 和多进程测试 |

不引入 Node 服务、数据库、系统包安装或新的浏览器扩展，不实现另一套 GDB、编译器封装或测试结果界面。

## 文件位置

| 用途 | 位置 |
| --- | --- |
| 本任务包与后续交接记录 | `/tmp/nvim-cp-cache/` |
| **待创建**的插件源码 | `/home/gordon/.config/nvim/local/cp-cache.nvim/` |
| 正式运行缓存 | `/home/gordon/.config/nvim/.cache/cp-cache/v1/` |
| 开发验证产生的文件 | `/home/gordon/.config/nvim/.verify/cp-cache/` |
| 既有使用说明 | `/home/gordon/.config/nvim/docs/competitive-programming.md` |

`/tmp` 只获准放 AGENTS、设计、交接和进度文档；不要把这一例外扩大为修改其他目录的授权。插件通过 lazy.nvim 的本地 `dir` 加载。不要让正式配置依赖 `/tmp`，它可能在重启时被清理。

## 给下一位实现者的启动提示

可以直接交给后续 AI：

> 阅读 `/tmp/nvim-cp-cache/AGENTS.md`、`HANDOFF.md`、`DESIGN.md` 和 `PLAN.md`，按既定方案实现 cp-cache.nvim。代码放在 `/home/gordon/.config/nvim/local/cp-cache.nvim/`，分阶段完成测试后接入现有配置。所有开发产生的文件限定在 `.config/nvim`；交接与进度文档放在 `/tmp/nvim-cp-cache/`。不要修改已安装插件源码，不要重写 GDB 和编译系统。先完成 P0 兼容性验证，再依次完成 P1–P5；未完成集成与验收前不要宣称缓存已经可用。

## 为什么选择扩展现有环境

本机 CompetiTest 的 `testcases_directory` 是相对源码目录的字符串，并没有独立题库索引。只修改为绝对路径不能工作。
通过自定义格式替换可以绕过单文件路径限制，但还需处理索引、接收新题/比赛、旧样例、不同源码之间的关联以及转换命令，已经超出一项简单设置。

调查到的 tuna.nvim 原生支持绝对样例目录，不能笼统声称“没有插件支持异地存样例”。但其题目信息默认保存在源码旁，迁移现有接口仍需适配；本轮未验证其完整替代方案。因此选择在当前环境上开发聚焦缓存管理的扩展。此选择是本项目的取舍，并非对所有现成插件能力的否定。

依据：[CompetiTest 配置](https://github.com/xeluxee/competitest.nvim#configuration)、[tuna 样例目录与题目存储配置](https://github.com/FrancescoDerme/tuna.nvim/blob/main/lua/tuna/config.lua)、[Competitive Companion 协议](https://github.com/jmerle/competitive-companion#the-format)。具体本机接口见 HANDOFF；实施时以已安装版本为准。
