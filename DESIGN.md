# cp-cache.nvim 首版设计

本文保留首版设计契约，现已实现；实际验证与限制见 ACCEPTANCE.md。
用户后续指定在当前 Git 仓库开发，运行副本才放到配置目录；此要求优先于原任务包路径。

## 1. 范围与数据流

选择持久集中缓存，保留 CompetiTest 的运行与编辑界面，以及既有编译/GDB 设施。

```text
Competitive Companion ──> receiver ──> store ──> 题目文件 + 源码关联 + 索引
                                           ↑
                                  picker / editor / migrate
                                           ↓
                          get_testcases(source buffer)
                              ↙                      ↘
                 CompetiTest runner             现有 CPDebug
                        ↓                            ↓
                  cp_tool.py                   输入快照 + GDB
```

首版必须支持当前源码接收、新题/比赛接收、缓存搜索复用、增删改、批量运行比较、GDB 样例输入、旧样例迁移。临时模式、直接抓取题面、自动提交、云同步、对拍不在首版范围。

## 2. 模块与依赖方向

开发源码根目录为当前仓库 `/home/gordon/Coding/nvim-cp-cache/`；本机运行副本为
`/home/gordon/.config/nvim/local/cp-cache.nvim/`。

```text
lua/cp_cache/
  init.lua       setup、公开 API、命令、buffer 生命周期
  identity.lua   URL/题目 ID、源码规范路径、ID 校验
  store.lua      JSON 数据、关联、索引、锁、原子写入
  receiver.lua   Companion HTTP 接收、批次、导入策略
  adapter.lua    所有 CompetiTest 接口、runner/editor、兼容命令
  picker.lua     Telescope 搜索和 vim.ui.select 后备
  migrate.lua    只读旧样例并复制到 store
tests/
  minimal_init.lua
  run.lua
  fixtures/
doc/cp-cache.txt
```

不要为每个小函数新建模块。`identity` 不依赖 store/UI；store 不依赖 CompetiTest；receiver/picker/migrate 经 store 访问数据；adapter 不自己维护第二份题库。

## 3. 缓存与身份

默认根目录：`vim.fn.stdpath('config') .. '/.cache/cp-cache/v1'`。
不能直接使用默认 `stdpath('cache')`，那会落到用户本轮未授权修改的位置。测试通过 setup 注入 `.verify/cp-cache/store`。

```text
v1/
  problems/<problem_id>.json       权威题目与样例数据
  bindings/<source_hash>.json      源码 -> 题目关联
  index.json                      可重建的查询索引
  locks/                          写入锁，操作完成释放
  exports/<problem_id>/            显式导出的文本/msgpack，非权威数据
```

### 题目身份

- `https://codeforces.com/contest/1234/problem/A` 与 `/problemset/problem/1234/A` 共用 `cf-1234-A`。
- `/gym/1234/problem/A` 用 `cf-gym-1234-A`，不可与普通 contest 合并。
- 仅对已验证的 Codeforces 主机和明确支持的镜像做此规则；拒绝用子串匹配把 `codeforces.com.example.org` 识别成 Codeforces。未知主机走通用规则，不猜题号。
- 通用 URL 使用 `url-<完整 SHA256>`。规范化只去 fragment、规范化 scheme/host 大小写；不删除可能决定题目身份的 query/path。原始 URL 和规范 URL都可记录。
- 没有 URL 的手工题目用 `local-<规范源码路径 SHA256>`。不能仅以 `main.cpp`、标题或题目字母当 key。
- 路径 hash 用 `vim.fn.sha256`；文件存在时取 realpath。尚未创建文件时用 realpath(parent) 与 basename，消除相对路径和常见符号链接别名。
- 缓存文件名只来自校验后的 ID 或 hash；题目标题仅是展示字段。

### 一题、多份源码、重复使用临时源码

一个 source binding 指向一个题目；多个 binding 可以指向同一题目。多个解法共享该题样例，修改前显示题号/标题。

用户在同一个 `main.cpp` 接收另一道题时，只切换 binding，旧题仍在库中。明确提示当前题发生变化；取消则不改 binding。重命名源码后通过搜索重新关联，不做全盘文件扫描或内容指纹猜测。

不向源码注入 URL 注释，不创建 `.cph`、`.competitest.lua`、`.tuna.json` 或符号链接来维持关联。

## 4. JSON 契约

每题一个对象，metadata 与样例一次原子保存。示意字段如下（示例内容不是实际 Codeforces 样例）：

```json
{
  "schema_version": 1,
  "id": "cf-1234-A",
  "revision": 1,
  "name": "Example problem",
  "group": "Codeforces - Example round",
  "url": "https://codeforces.com/contest/1234/problem/A",
  "canonical_url": "https://codeforces.com/problemset/problem/1234/A",
  "updated_at": "2026-10-16T00:00:00Z",
  "tests": [
    { "id": 0, "input": "1\n", "output": "2\n", "origin": "received" },
    { "id": 1, "input": "", "origin": "manual" }
  ]
}
```

`tests` 是 JSON 数组；`id` 是唯一非负整数。空输入有效；有 `output: ""` 表示期待空输出，没有 output 字段表示无标准答案。保存样例时不 trim、不追加换行、不混淆这两种输出。未知 schema_version 报错，禁止自动覆盖。

从 Companion 取得的 timeLimit、memoryLimit、interactive、输入输出类型可保存到 metadata，但不自动改变当前运行限时、内存限制或把交互题当普通题运行。

binding 对象必须有 `schema_version`、`source`（完整规范路径）、`problem_id`；文件名是 source hash，并在读取时校验对象 source 与请求路径一致。

index 保存 ID、标题、分组、URL、更新时间、样例数等摘要。**problems 文件才是事实来源**。索引丢失/损坏可重建，不因此删除题目；搜索需要能发现另一 Neovim 实例刚写入的题目，不能无限使用旧内存索引。首版每次打开 picker 扫描 problems 元数据并刷新索引即可，先不写复杂文件监视器。

### 写入、冲突和失败

- 在目标文件同目录创建独占临时文件，写完关闭后 rename；临时文件名包含进程号和随机/高精度时间成分，禁止固定 `file.tmp`。
- 对同一题目的 read-modify-write 加独占锁，读当前 revision；用户长时间打开 editor 后保存时如 revision 改变，提示重新加载/取消，不静默覆盖别人的修改。
- 锁采用原子 mkdir 或 `uv.fs_open(..., 'wx', ...)`；忙时异步等待或提示重试，不阻塞主线程。stale lock 需有明确检测/恢复流程，不能一见旧时间就抢走活锁。
- 每个 binding 原子保存；先保存题目，再保存 binding，最后更新可重建索引。任一失败报告具体阶段。题目成功而绑定失败时，题目仍可搜索，允许重试关联。
- 损坏题目在 picker 显示错误或跳过并通知，不把空样例写回原文件。
- 删除最后一个样例仍保留题目/关联，避免旧样例迁移再次自动“复活”。
- 首版不做自动 TTL 删除。`forget` 只解除当前 binding；`remove` 需显示关联源码数量并确认删除，禁止静默丢弃手工样例。

## 5. 对外 API 与使用行为

以下 API 参数以明确 source buffer 为准，不在异步回调里重新猜当前文件。

| 接口 | 契约 |
| --- | --- |
| `setup(opts)` | 可重复调用；配置 cache_root、port 等；不自动开启监听 |
| `get_testcases(bufnr)` | 成功返回新的数字键表；无绑定返回空表；错误返回 `nil, error` |
| `receive(mode, bufnr)` | mode 为 testcases/problem/contest/persistently；testcases 捕获发起时的源码 |
| `stop_receive()` / `receive_status()` | 生命周期可重复关闭；退出 Neovim 时释放 socket |
| `run(bufnr, opts)` | opts 支持 compile、only_show、numbers；交给 adapter |
| `edit(bufnr, id)` / `add(bufnr)` / `delete(bufnr, id)` | store 为权威；编号缺省用 picker；删除确认 |
| `pick(bufnr)` | 按题号/标题/URL 搜索；选择后关联当前源码，不覆盖源码 |
| `migrate(bufnr)` | 从旧存储复制；默认不覆盖已有缓存，不删除旧文件 |

`get_testcases` 返回 CompetiTest 形状 `{ [0] = {input=..., output=...}, ... }`；不存在的 output 保持 nil，其他元数据不泄漏给 runner。调用方可以修改返回表而不污染 store 的内存对象。

新增统一 `:CPCache` 命令，子命令至少包括 `receive`、`find`、`info`、`migrate`、`forget`、`remove`、`reindex`、`export`。

新增 C++ 快捷键建议：`<leader>cf` 搜索并关联、`<leader>cI` 显示当前关联；先查冲突。保留 `ct/cs/cr/cP/cC/ca/ce/cx/cu/cd` 原有含义。所有新命令必须有补全与错误提示。

`CPCache info` 展示题目、规范源码路径、缓存文件位置、样例数；不要把内部 hash 等实现字段堆进常规运行结果面板。

## 6. CompetiTest 适配：不编辑第三方源码

在 `adapter.lua` 内加载 CompetiTest config，构造/复用 runner；调用 `run_testcases` 时直接传缓存数据。runner 复用 CompetiTest `commands.runners[bufnr]`，使其既有 resize 能找到它。运行前结束旧运行；退出/卸载源 buffer 时结束进程并清理 runner 和相应 UI 资源。P0 验证具体 UI 清理方法。

编辑和新增使用现成 widgets.editor，把保存回调指向带 revision 检查的 store 写入。widget 的取消不得落盘。同一 buffer 的运行、编辑和调试都解析同一 binding。

保留 Python compile/run 配置、比较方式、3 秒默认限时、串行测试和现有界面按键。测试过程不为了使用插件而把样例复制回源码目录。

### 兼容已有 `:CompetiTest` 命令

不能只换 leader 键而让旧命令偷偷写回源码目录。CompetiTest setup 完成后，由 adapter 注册一个兼容的 Ex 命令分发器：

- 托管的 C++ 源码 buffer 中，run/run_no_compile/show_ui/add_testcase/edit_testcase/delete_testcase 转到 adapter/store。
- receive 的 testcases/problem/contest/persistently/status/stop 转到新 receiver；status/stop 不依赖当前 UI 窗口是不是 C++。
- 非托管语言仍调用保存的 `require('competitest.commands').command` 函数，不能通过执行同名 Ex 命令递归回自己。
- 保留参数解析、命令补全、`-bar` 行为。lazy 首次加载与重复 setup 各验证一次。
- `convert` 在托管 C++ 下改为**缓存内格式导出**：files_to_singlefile 导出 msgpack，singlefile_to_files 导出文本，auto 在上次导出的格式间切换；权威 JSON 不变。说明这一差异，并提供 `CPCache export files|msgpack`。非托管语言保持原语义。旧源码旁样例的搬入用 migrate。

兼容命令只接管插件命令入口，不全局覆盖 fs 函数、不修改 CompetiTest 的存储模块、不窥探私有闭包。所有依赖接口验证收敛到 adapter 中，加载失败就报告依赖错误，不静默退回在源码旁写样例。

## 7. 接收与批量导入

为保留 URL/标题与建立题目索引，自建一个小型 Companion 接收器。解析题面仍由现有浏览器扩展完成。

- 主机固定 `127.0.0.1`，默认端口 27121；不自动开服务，不在后台抓取题面。端口冲突提示用户停止旧接收器。
- 使用 uv TCP，按 HTTP 头和 Content-Length 拼接请求；不可把一次 TCP chunk 当完整 JSON，也不可只取最后一行或等待 EOF 才认为包完整。
- 实现 POST 与所需 OPTIONS 响应、Connection: close，按字节计 Content-Length。头大小、请求体大小和空闲连接有上限；默认建议 16 KiB、8 MiB、10 秒，失败关闭连接并报告。
- 解析/字段校验失败不能抛出未捕获异常导致 Neovim 崩溃。UI 和 buffer API 通过 schedule 回主线程。
- 校验 tests 的 input/output 字符串、URL、batch.id/size；网络字段不能决定任意输出路径。
- 批次按 batch.id 收集，按规范题目 ID 去重，重复 POST 不使 size 错算。不混合两个 contest；未完成批次有超时提示。
- 成功接收排队可返回 HTTP 202；只有保存完成后才在 Neovim 提示“已保存”。取消或写入失败不能显示保存成功。
- 单次 testcases 捕获当前 buffer 的规范路径；用户切换 buffer 后仍绑定原来源，原 buffer 关闭则明确取消或请用户重新选择，不能误绑定。
- 重复导入同一题先提供“替换已接收样例（保留手工） / 追加 / 取消”。完全相同的重复 payload 不重复追加。更新当前题目不能抹掉另一题。
- 新题/比赛创建沿用现有模板与路径选择；只在用户选择的目录创建源码。样例始终写集中缓存。同名/已存在源码必须提示，不自动覆盖。
- 复用 `received_problems_path`、`received_contests_directory`、`received_contests_problems_path` 的当前字符串规则和函数形式；模板是原样复制还是展开受现有 evaluate_template_modifiers 影响。路径和模板的额外 modifier 实现集中在 receiver，不在各入口重复实现。
- 持续接收保持现有选择 testcases 或完整题目的体验。stop/退出关闭监听、连接、timer 和待处理队列。

必须使用 Companion 协议 fixture 和真实本机 HTTP 测试；浏览器插件点击再作为人工验收。

## 8. 调试、迁移、回退

现有 `cp.debug()` 的样例读取改成 `cp_cache.get_testcases(bufnr)`；错误时提示并中止这次样例启动，不把读错缓存误当成没有输入。`M.test` 保持设置 release/sanitize 的现有逻辑，随后调用 adapter runner。

继续使用现有 `.runtime/inputs/` 快照、GDB 参数、binary 和 cwd。启动时快照内容必须与选中样例逐字节一致；样例 0、空输入均支持。手动文件输入/交互终端/EOF 完全保留。

迁移只读取当前源文件对应的旧 `testcases/<FNOEXT>.<N>.in/out`，并支持已存在的 CompetiTest 单文件格式。不要递归扫描整个家目录。没有 binding 且发现旧样例时可以提示迁移；首次 demo 体验需在接入时把配置目录内示例复制到缓存，使旧演示仍能直接运行。已有 binding（即使样例空）不重新迁移。

只有缓存复制与回读校验成功才报告迁移成功；旧样例一律保留。本任务不授权清理用户源目录。

回退时恢复本次备份的配置入口，移除本地插件的 lazy 接入；缓存数据保留，旧样例保留，GDB 与编译器配置不受影响。不要用更早的“添加竞赛环境前”备份做这次回退。
