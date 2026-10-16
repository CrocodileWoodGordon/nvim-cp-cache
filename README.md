# cp-cache.nvim

为现有 C++ 竞赛环境提供持久、集中的样例库。接收、编辑、搜索、CompetiTest 测试和 GDB 调试读取同一份缓存；源码目录只保存源码。

**已实现 P0–P5 的功能，开发与验收记录见 [PROGRESS.md](PROGRESS.md) 和 [ACCEPTANCE.md](ACCEPTANCE.md)。** 本机已接入 NvChad；浏览器扩展按钮点击仍需人工验收。每个开发小步均保留 Git 提交。

## 使用环境前提

这不是一整套 Neovim 配置，也不安装编译器或浏览器扩展。本仓库扩展已经存在的 CompetiTest / C++ / GDB 工作流。

| 前提 | 要求与本次实测环境 |
| --- | --- |
| 操作系统 | 实测 Arch Linux；文件权限、锁恢复和 PTY 验证按 Linux 环境实现，未验收 Windows |
| Neovim | 代码使用 0.10+ API 与 LuaJIT；**实际验收 0.12.6**。完整 NvChad 与其他依赖可能要求更高版本，不承诺整套配置可在 0.10 运行 |
| 插件环境 | 本机 NvChad v2.5 + lazy.nvim；CompetiTest 和 nui.nvim 必须先安装并配置 |
| CompetiTest | 兼容探针锁定 `b42c06ca308906f07912ba9aff015ac2c0831f85`；nui `10fc361835c856ba4233ef5ea135b919bf3dce97`。使用了其内部导出接口，更换版本需重跑兼容测试 |
| 编译与运行 | 本机现有 `~/.config/nvim/scripts/cp_tool.py`、`python` 和支持 GNU++20/ASan/UBSan 的 G++；实测 Python 3.14.8、GCC 16.2.1。插件不另建编译系统 |
| 调试 | 现有 `cp` 模块、nvim-dap、dap-ui、nvim-nio；GDB 必须支持 `--interpreter=dap`，实测 18.1 |
| 搜索与 LSP | Telescope 可选，缺少时用 `vim.ui.select`；本机真实 Telescope 与 clangd 23.1.1 已验收 |
| 浏览器导入 | 同一台机器上的 Competitive Companion；能访问题面；本地端口 27121 可用。SSH 场景需自行转发端口 |
| 权限 | 配置内缓存根目录可写；缓存路径（含父目录）不允许符号链接。调试需要系统允许 ptrace |

C++ Treesitter parser 用于高亮和源码行末变量显示，不是样例库或 GDB Scopes/Stacks 的前提。本轮没有安装 parser，也没有升级依赖。Rust 验证覆盖原键位，未验收 Cargo 项目内的 Rust LSP。

## 安装与接入

开发仓库在 `/home/gordon/Coding/nvim-cp-cache`，本机运行副本在 `~/.config/nvim/local/cp-cache.nvim`。正式配置不依赖开发仓库或 `/tmp`。

将本仓库复制/克隆到 `~/.config/nvim/local/cp-cache.nvim`。在现有 CompetiTest lazy spec 中配置依赖和顺序：

```lua
{
  "xeluxee/competitest.nvim",
  dependencies = {
    "MunifTanjim/nui.nvim",
    { dir = vim.fn.stdpath("config") .. "/local/cp-cache.nvim",
      name = "cp-cache.nvim", lazy = true },
  },
  ft = "cpp",
  cmd = { "CompetiTest", "CPCache" },
  opts = function() return require("configs.competitest") end,
  config = function(_, opts)
    require("cp_cache.adapter").setup_dependency(opts)
    require("cp_cache").setup({
      cache_root = vim.fn.stdpath("config") .. "/.cache/cp-cache/v1",
      port = 27121,
    })
  end,
}
```

这里的 `configs.competitest` 必须是你已有的编译/运行配置；本机配置继续调用 `cp_tool.py`，保持串行、3 秒限时、squish 比较和原 UI 按键。`ft = "cpp"` 保证旧命令在首次 C++ 操作前已接管。

本机精确改动见 [integration/nvim.patch](integration/nvim.patch)：只修改竞赛 lazy spec、`cp.init` 的测试/调试取样例入口、CPP 键位和使用教程。GDB adapter、断点/栈/变量辅助功能、编译器脚本和第三方插件源码均保留。

本仓库的开发部署工具仅适用于文档描述的已有本机配置：

```sh
python3 tools/verify.py install
```

它创建任务文件备份、核对原始或上次部署的 SHA256，再应用变更。遇到用户并发修改会拒绝覆盖。不要把此工具作为任意新配置的通用安装器。

## 五分钟使用

重启 Neovim，打开具名 C++ 源码。已有配置内 demo 的旧样例已复制到正式缓存：

```sh
nvim ~/.config/nvim/examples/cp-demo/main.cpp
```

空格是本机 leader。按 `空格 ct` 编译比较两个样例，输出应为 `15`、`6`；`空格 cs` 使用 sanitize。`q` 关闭结果，`空格 cu` 重开。把光标放在 demo 第 8 行，F9 设置断点，F5 选择样例，F5 继续到断点，F10 单步；`空格 dt` 结束调试。

| 本机 C++ 键位 | 功能 |
| --- | --- |
| `空格 cr` | 接收一次当前源码的样例 |
| `空格 cP` / `空格 cC` | 接收新题 / 整场比赛，选择源码创建路径 |
| `空格 cf` / `空格 cI` | 搜索关联已有题目 / 查看当前关联 |
| `空格 ca` / `空格 ce` / `空格 cx` | 增加 / 编辑 / 删除共享样例 |
| `空格 ct` / `空格 cs` | release / sanitize 编译比较全部样例 |
| `空格 cu` | 重开测试结果面板 |
| `空格 cd` / F5 | 编译调试版，选择样例、输入文件、交互终端或 EOF |
| `空格 cb` / `空格 cR` | 编译 debug / 编译后在交互终端运行 |
| `空格 c?` | 本机完整竞赛环境教程 |

`cf/cI` 由本机集成添加；插件本身不创建全局键位。NvChad 的 `ds/ch/fm`、Rust buffer 映射、原 F9 等调试键继续保留。

## 从浏览器导入

安装 Competitive Companion，在需要时将扩展 Custom ports 设置为 `27121`。插件不自动监听，不自行抓取 URL。

1. 在 Neovim 打开并命名 `A.cpp`，执行 `:CPCache receive testcases` 或按 `空格 cr`。
2. 打开浏览器题目页，点击扩展绿色 `+`。
3. 以 Neovim 的“已保存”提示为准；HTTP 202 仅表示排队。按 `空格 ct` 测试。

等待接收时切换窗口不会改变归属；关闭或重命名发起接收的 buffer 会取消该次关联。testcases 模式不会创建新源码。

```vim
:CPCache receive problem
:CPCache receive contest
:CPCache receive persistently
:CPCache receive status
:CPCache receive stop
```

problem/contest 沿用 CompetiTest 的模板、路径字符串/函数和路径提示设置。新文件只在选择的目录创建；已有源码会提示使用现有内容、另选路径或取消。没有自动覆盖源码。持续接收单题时可选仅样例或完整题目。比赛按 batch.id 收集并去重，残缺批次超时后可重发。

重新导入同题可选“替换已接收样例（保留手工）/追加/取消”；相同 payload 不重复追加。手工编辑会将该样例标为 manual。一个 `main.cpp` 改收另一题时会确认切换关联，旧题仍在库中。

## 搜索、共享与源码重命名

`:CPCache find` / `空格 cf` 按题号、标题、分组或 URL 搜索；选择只建立关联，不改源码。无 Telescope 时退回选择列表。每次搜索重新扫描题目文件，能发现其他 Neovim 实例的新数据。

多个解法可以关联同一题，增删改样例会共享。编辑标题和删除确认会显示题目；并发修改导致 revision 冲突时，当前编辑不会静默覆盖，可重新加载或取消。

源码移动/重命名后，打开新路径，执行 `CPCache find` 选择原题即可。插件不凭 basename 猜题，也不扫描家目录。重命名前可选 `CPCache forget` 解除旧关联；题目和样例仍在库中。旧路径关联不会自动迁移。

## 样例编辑、测试与调试

未关联源码第一次新增会建立本地手工题。编辑器左边输入、右边预期输出，`Ctrl-S` 保存，普通模式 `q` 取消。空白输出保存时明确选择“期待空输出”或“无标准答案”。编号 0、空输入、缺省 output、中文、CRLF 和末尾换行在 store 中逐字节保存，不 trim、不补换行。

结果面板保持 CompetiTest 原操作：`R` 重跑当前，`Ctrl-R` 重跑全部，`K` 停当前，`Ctrl-K` 停全部，`d` 切换 diff，`i/a/o/e` 查看输入/预期/stdout/stderr，`q` 关闭。重跑读取最新缓存。编译失败不会启动旧二进制。

测试比较仍按现有 `output_compare_method` 执行；默认 squish 会忽略多余空白，不能代替交互器、特殊判题或浮点容差判断。接收的时限/内存仅保存为 metadata，不自动改变本机限制。

`:CPDebug 0` 可直接选择编号 0。测试和调试读取同一关联；调试启动时将输入复制到 `~/.config/nvim/.runtime/inputs/`，编辑样例不会改变已启动会话。输入文件、交互 PTY、EOF、原断点、Scopes、Stacks、Watches、表达式查询与 GDB 控制台沿用原配置。

## 缓存位置、迁移与导出

默认根目录：**`~/.config/nvim/.cache/cp-cache/v1/`**，可用 `setup({cache_root=...})` 指定。关闭 Neovim 后数据仍保留。

```text
v1/
  problems/<id>.json        每题的权威 metadata、revision 和样例
  bindings/<hash>.json      规范源码路径到题目的关联
  index.json               可重建搜索摘要
  locks/                   短期写锁
  exports/<id>/            显式导出的 revision 快照
```

CF contest/problemset URL 共用 ID，Gym 独立；只识别精确 `codeforces.com` / `www.codeforces.com` 主机。其他 URL 使用完整 SHA256，保留 query；标题不会作为缓存路径。源码按规范完整路径关联，支持存在文件与父目录的 realpath。

```vim
:CPCache info
:CPCache migrate
:CPCache migrate files
:CPCache migrate msgpack
:CPCache export files
:CPCache export msgpack
:CPCache reindex
```

迁移只读当前源码对应的旧 `testcases/` 文本或单文件 msgpack，复制并回读校验后建立关联；旧文件不动。已有缓存关联（包括零样例）不覆盖。如果手工题已在库中但解绑，请搜索重新关联。

托管 C++ 的旧 `:CompetiTest` run/edit/add/delete/receive/show_ui 全部转到缓存。`convert files_to_singlefile` 改为缓存内 msgpack 导出，`singlefile_to_files` 导出文本，`auto` 切换上次导出格式；权威 JSON 不变。导出是 revision 快照，删除题目后仍保留。非 C++ 继续走原 CompetiTest 语义。

## 清理、出错恢复与回退

`:CPCache forget` 只解除当前源码关联；`:CPCache remove` 显示题目和关联源码数量，确认后删除题目全部样例（包括手工）与关联。源码、旧 testcases 和导出快照保留。没有 TTL 自动删除。

损坏 JSON/未知 schema 会报出具体文件并拒绝覆盖；不要用空 JSON 覆盖。索引损坏可以 `CPCache reindex` 重建，题目文件才是事实来源。写锁忙时稍后重试；确认旧进程已退出后，可以执行：

```vim
:CPCache unlock cf-1234-A
:CPCache unlock binding
```

后者恢复当前源码的关联锁。只在锁内 PID 确认不存在时解锁，活进程/权限未知均拒绝；不按“锁很旧”判断。锁内容损坏需要人工检查具体锁文件。

本次配置备份在 **`~/.config/nvim/backups/cp-cache-2026-10-16/`**。先停止接收/调试并退出 Neovim，在本仓库运行：

```sh
python3 tools/verify.py rollback --check
python3 tools/verify.py rollback
```

工具仅恢复本次备份的四个配置/教程文件，并拒绝覆盖部署后的用户修改。再启动即恢复原 CompetiTest 工作流；本地插件副本、缓存、编译产物和旧样例都保留。不要用 `2026-10-14-before-cp` 做这次回退，那会撤掉已有 GDB 配置。手动回退也只恢复本次备份的同名四个文件。

## 开发与实际验证

测试工具先复制代码到配置目录；所有 fixture、XDG data/state/cache、TMPDIR、日志都在 `~/.config/nvim/.verify/cp-cache/`。构建与输入快照继续使用原配置内 `.build/`、`.runtime/inputs/`。不启动 lazy 全量升级，不安装系统包，不修改第三方源码。

```sh
python3 tools/verify.py probe       # 真实 CompetiTest 内存 runner/editor
python3 tools/verify.py lazy_probe  # 实际 lazy 首次命令与重复 setup
python3 tools/verify.py run         # store、工作流、HTTP、边界验收
python3 tools/verify.py resize      # 真实 TUI/PTY 改变尺寸
python3 tools/verify.py full        # 完整 NvChad、clangd、Telescope、原 CP 入口
python3 tools/verify.py gdb         # 真正断点、递归栈、局部变量、watch、单步
```

结果和限制逐项列在 [ACCEPTANCE.md](ACCEPTANCE.md)。真实 GDB 已通过；A17 的启动参数捕获单列，未用它冒充断点调试。浏览器扩展点击与外网题面受当前代理没有浏览器交互入口限制，标为 BLOCKED（待人工）；本地 HTTP 协议导入已通过。

设计、原任务约束和阶段要求分别保留在 [DESIGN.md](DESIGN.md)、[AGENTS.md](AGENTS.md)、[PLAN.md](PLAN.md)；用户后续指定的仓库开发路径优先。`:help cp-cache` 提供命令与 API 速查。
