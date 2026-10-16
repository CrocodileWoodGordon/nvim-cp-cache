# 分阶段实现与验收

当前所有开发阶段均为**待开始**。这份计划不能作为测试通过记录。

## P0：验证依赖接口与建立隔离测试

交付：插件测试目录、最小加载配置、真实 CompetiTest API 探针、本轮配置备份清单。

1. 重读现有文件和锁定版本，确认没有用户新修改；创建本轮相关配置备份。
2. 在 `.verify/cp-cache/` 下准备源码、样例 fixture、缓存、临时目录；最小配置只加载 CompetiTest/nui 和待开发插件。
3. 用内存 `{[0]=...}` 驱动真实 runner，验证编译和两个样例，确认源目录无样例文件。
4. 验证真实 widgets.editor 的保存/取消回调、runner 关闭/重开/窗口 resize 与 buffer unload 清理；查清需要的具体方法。
5. 验证 CompetiTest Ex 命令在 lazy 首次加载后能被 adapter 的分发器接管，重复 setup 不递归。

完成标准：接口与生命周期有实际测试证据。此阶段发现不兼容应修正 adapter 设计并记录原因，不能悄悄切换或升级依赖，也不能修改第三方代码。

## P1：身份、题目存储与源码关联

交付：identity.lua、store.lua、对应测试。

1. 实现 DESIGN 中题目 ID、URL 归一化、源码规范路径。
2. 实现校验、原子 JSON 读写、revision/锁、binding、可重建索引。
3. 实现增删改、绑定/解绑、空输入和缺省输出语义。
4. 实现查询、损坏文件处理、多实例冲突处理。

完成标准：同名不同目录互不串题；同题可共享；重启持久化；索引丢失可恢复；失败不破坏旧数据。

## P2：运行、编辑、搜索与迁移

交付：adapter.lua、picker.lua、migrate.lua、基本 CPCache 命令。

1. 由缓存生成数字键样例表，驱动现有 runner/editor/picker。
2. 接入 Telescope 查题号/标题/URL，后备 `vim.ui.select`；选择仅修改 binding。
3. 当前源码无绑定时允许手工新建题目；已有题目显示来源，防止误改共享数据。
4. 只读旧样例的迁移与缓存内导出。
5. 保留运行 UI 的 rerun、kill、diff、stdin/expected/stdout/stderr 查看行为。

完成标准：不依赖接收器即可用 fixture 完成“关联 -> 编辑 -> 运行 -> 再编辑 -> 重跑”，读写都只在缓存。

## P3：Companion 接收

交付：receiver.lua、单题/比赛 fixture、协议与实际本地 TCP 测试。

1. 实现分块 HTTP、响应、输入校验、监听生命周期和端口占用错误。
2. 当前源码接收、题目 metadata、重复导入策略、发起 buffer 绑定。
3. 批次去重/超时，接收新题与整场比赛，沿用模板与路径选择。
4. 持续接收、取消、stop、退出清理；所有模式都走统一 store。

完成标准：能在 `.verify` 的干净源码目录通过 HTTP 导入单题与两题比赛，目录内只有允许创建的源码。浏览器不可用不阻碍 fixture 验证；不能只测试直接调用 ingest。

## P4：接入用户配置并保留原工作流

交付：最小配置差异、CPP 键位、CPDebug/CPTest 接入、兼容命令。

1. 在 `lua/plugins/competitive.lua` 添加本地 dir spec，明确依赖加载顺序；正式配置不引用 `/tmp`。
2. 增加 setup 与命令入口，保留原有编译/运行选项。
3. `cp.init` 中测试和调试统一读取 cp_cache；不要改其 GDB 输入快照/终端/重启逻辑。
4. C++ buffer 保留全部既有竞赛键位，再加查找/信息入口；验证 Rust 和 NvChad 键位。
5. 实现 DESIGN 的 `:CompetiTest` 兼容分发，防止用户沿用旧命令时样例写回源码旁。
6. 从配置内 demo 的旧样例复制到缓存，保留原 fixture 与旧测试脚本的可运行性。

完成标准：重启完整 NvChad 后通过原有快捷键完成导入、编辑、比较和选择样例调试，无循环依赖、缺失模块或新增键位覆盖。

## P5：验收、教程、回退与交接

交付：验收结果、更新后的中文教程、回退说明、PROGRESS.md。

完成下表，不通过的项必须修复；被环境限制的项单独标 BLOCKED，并记录可复现命令和人工验收步骤。不要把开发阶段未完成归因于环境。

| 编号 | 验收场景 | 预期结果 |
| --- | --- | --- |
| A01 | 首次创建手工样例，退出重开 | 样例、关联持久化；源目录未增加样例/元数据 |
| A02 | 两个目录均名 main.cpp；同目录 A.cpp/B.cpp | 未绑定同题时互不串题；显式绑定同题时共享 |
| A03 | 同一 CF 题的 contest/problemset URL；Gym URL | 前两者同 ID，Gym 独立；恶意相似 host 不误识别 |
| A04 | 同一 main.cpp 先收题 A 再收题 B；再搜索 A | 当前关联正确，A 仍可查；取消切换不更改数据 |
| A05 | 样例 0、空输入、空输出、无输出、中文、CRLF、末尾换行 | 字节保留；期待空输出与没有答案不混淆 |
| A06 | 新增、编辑、删除、取消编辑、删除最后一个样例 | 缓存与 UI 一致；空题不会触发旧样例复活 |
| A07 | release/sanitize 跑 demo 两个样例；故意错误程序 | 正确输出 15/6；错误判为 WA；编译失败不跑旧二进制 |
| A08 | 慢程序、停止、重跑、关闭/重开 UI、resize、卸载 buffer | 限时/kill 生效、无残余进程、UI 生命周期正常 |
| A09 | 发送分片 HTTP、中文 Content-Length、无换行 JSON、错误 JSON | 完整包正确导入，错误包提示且服务仍可用 |
| A10 | 同端口占用、停止再启动、退出 | 明确冲突，正常释放 socket/timer |
| A11 | 接收等待时切换/关闭源 buffer | 不绑定到错误文件，不对无效 buffer 执行操作 |
| A12 | 两个交错比赛批次、重复 POST、超时的残缺批次 | 不串批、不重复计数；超时可恢复 |
| A13 | receive problem/contest/persistently 与模板/路径选择 | 仅创建用户选定源码，样例和索引全部在 cache |
| A14 | 复制旧 in/out 和 msgpack 样例，再重复迁移 | 内容一致；旧文件不变；已有 cache 不被覆盖 |
| A15 | 两个 Neovim 实例修改同题、索引缺失/损坏、题目损坏、写入失败 | 冲突可见、索引重建、原数据保留，不假报成功 |
| A16 | 特殊路径含空格/中文/单引号；源码软链；重命名后重新关联 | 正确定位，没有 shell 解析问题，不凭 basename 猜题 |
| A17 | CPDebug 0/其他样例、编辑后的样例、输入文件/交互/EOF | DAP 收到当前样例快照；已有输入分支均保留 |
| A18 | 真实 GDB 暂停、单步、递归栈、local、watch/eval | 使用缓存样例运行；受 ptrace 限制时单列人工验收 |
| A19 | 原 :CompetiTest 命令与新增 CPCache 命令；lazy 首次触发 | 托管 C++ 都走 cache，命令补全、原运行键可用 |
| A20 | 原 NvChad ds/ch/fm、Rust 文件、LSP、F9 等 | 与接入前相同；新键只在 C++ 生效 |
| A21 | 导出、解除关联、删除题目、缓存根含软链 | 只写/删本插件缓存；删除共享题目有提示与确认 |
| A22 | 正式配置与源码目录快照 | 无 /tmp 运行时依赖；源码目录只有用户选择的源码变化 |

## 隔离运行命令

先建立下面的目录；这是未来执行者使用的示例，本轮没有运行这些开发测试。

```sh
mkdir -p /home/gordon/.config/nvim/.verify/cp-cache/{data,state,cache,tmp,fixtures,store}
env \
  XDG_DATA_HOME=/home/gordon/.config/nvim/.verify/cp-cache/data \
  XDG_STATE_HOME=/home/gordon/.config/nvim/.verify/cp-cache/state \
  XDG_CACHE_HOME=/home/gordon/.config/nvim/.verify/cp-cache/cache \
  TMPDIR=/home/gordon/.config/nvim/.verify/cp-cache/tmp \
  NVIM_CP_OFFLINE=1 \
  PYTHONDONTWRITEBYTECODE=1 \
  nvim --headless -i NONE \
  -u /home/gordon/.config/nvim/local/cp-cache.nvim/tests/minimal_init.lua \
  -l /home/gordon/.config/nvim/local/cp-cache.nvim/tests/run.lua
```

minimal_init 应将本地 cp-cache、已有 CompetiTest 和 nui 的路径加入 runtimepath，关闭 swap/backup/持久 undo；不要引导 lazy 下载插件。测试入口捕获异常并退出非零状态。测试 fixture 与报告限定在 `.verify/cp-cache` 内，不使用全局临时目录。

完整 NvChad 验证仍使用这些 XDG/TMPDIR 隔离变量，但正常读取用户 init；必要时在隔离 data 中生成主题缓存。C++ 文件具名打开，按实际启动机制触发 UIEnter，避免空 dashboard 干扰。

核心验收用**目录快照差异**证明无源码旁文件，不只断言 `testcases/` 不存在。比较时排除用户明确要求创建/保存的 `.cpp`，不要把本任务允许写入的全局缓存也误判成污染。

## 每阶段交接格式

`PROGRESS.md` 每阶段一条记录：阶段 / 完成文件 / 实际命令 / PASS、FAIL、BLOCKED / 下阶段入口 / 剩余问题。少量准确证据优于粘贴整段终端日志。

最终用户说明至少包含：缓存实际路径、重启后使用方式、浏览器导入、搜索重新关联、批量测试、调试、旧样例迁移、清理与回退。明确列出哪些功能已实测，哪些仍需用户本机验证。
