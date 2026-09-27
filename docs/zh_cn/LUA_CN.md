# Lua 插件

插件也可以就是一个 Lua 脚本——无框架、无需安装 Python。WayRun 二进制自身承载
它（`wayrun --lua-host`），与 Python 主机讲同一套 JSON-RPC 接口，启动只需毫秒级，
启动器的一切能力都通过一张 `wayrun` 表可达。

## 编写脚本

脚本返回一组插件表，每个表即一个插件：

```lua
#!/usr/bin/env -S wayrun --lua-host
return {
  {
    id = "my-plugin",                    -- 必须与 plugins.toml 条目一致
    name = "My Plugin",
    icon = wayrun.icon("builtin:globe"), -- 绝对路径，或 nil
    description = "简短描述",
    env = { "MY_TOKEN" },                -- 可读的环境变量名
    search = function(text)              -- 路由查询的候选行，按序返回
      return {
        { title = "You searched: " .. text,
          on_click = { type = "copy", text = text } },
      }
    end,
    top = function() end,                -- 可选：空查询视图
    forget = function(action) end,       -- 可选：认领一行以从历史移除
  },
}
```

行即通信协议中的结果项：`title`、`summary`、`on_click`（一个动作）、`icon`、
`ephemeral`、`actions`、`badge`。不需要构造器——写成结果项形状的表即可，例如
`on_click = { type = "open", uri = "https://example.com" }`。

插件表同时就是它的 manifest：`env` 列出它可读的环境变量名，逐字匹配、不支持通配。
名单之外的名字会抛出（与 `fs.read` 越界一致），声明了但没设置的返回 nil（与文件
缺失一致）；读取归属于某次插件调用，脚本自身加载时读不到——脚本本来要从环境里取的
路径，用 `wayrun.home()` 与 `wayrun.cache_dir()` 就够了。

## `wayrun` 表

| 调用 | 作用 |
| --- | --- |
| `wayrun.home()` | `$HOME`，否则 nil |
| `wayrun.cache_dir()` | 启动器的缓存目录，否则 nil |
| `wayrun.icon(spec)` | 把 `builtin:…`、主题图标名或 `papirus:…` 解析为绝对路径；未命中为 nil |
| `wayrun.urlencode(text)` | 按 URL 需要做百分号编码 |
| `wayrun.t(key, args)` | 取启动器自带文案表中的一条，`%{name}` 由 `args` 填充 |
| `wayrun.log(message)` | 以脚本名义写入启动器的 journal |
| `wayrun.web_search_engine()` | 配置的搜索引擎，如 `"google"` |
| `wayrun.time()` | Unix 秒，用于签名与缓存 TTL |
| `wayrun.env(name)` | 插件在 `env` 中声明的变量；未设置则为 nil；未声明的名字抛出 |
| `wayrun.which(name)` | 启动器 `$PATH` 上某个可执行文件的路径，否则 nil；与 `run` 行的命令将看到的 PATH 相同 |
| `wayrun.script_dir()` | 脚本自身所在目录，用于携带图标等文件 |
| `wayrun.plugin_dir(id)` | 插件可读目录：`~/.config/wayrun/plugins/<id>` |
| `wayrun.fs.read(name)` | 读取上述目录中的文件；相对名，缺失返回 nil，越界报错 |
| `wayrun.toml.decode(text)` | TOML 进，表出 |
| `wayrun.json.decode(text)` / `wayrun.json.encode(value)` | JSON 进出 |
| `wayrun.fs.list(dir)` | `dir` 下的条目名，否则 nil |
| `wayrun.fs.stat(path)` | `{ mtime_ns, size }`，否则 nil |
| `wayrun.http.get(url, params?, options?)` | 阻塞式 GET，返回 `{status, headers, body}`；传输错误抛出；`params` 追加查询参数，其保留键 `headers` 为请求头表；`options` 是带 `timeout_ms`、`headers`、`ttl` 的表，或直接给一个毫秒数作超时 |
| `wayrun.http.post(url, params?, options?)` | 同上，发送一个 body：`json = value`、`form = {…}` 或 `body = "…"` 三选一；永不缓存 |
| `wayrun.crypto.sha256(text)` / `wayrun.crypto.md5(text)` | 小写十六进制摘要 |
| `wayrun.crypto.hmac_sha256(key, text)` | 小写十六进制 HMAC |
| `wayrun.crypto.base64_encode(data)` / `wayrun.crypto.base64_decode(text)` | 对原始字节做 base64 编解码；解码对垃圾输入返回 nil |
| `wayrun.sqlite.snapshot(path)` | 打开一份 SQLite 文件的不可变副本，返回句柄；同一文件返回同一句柄，句柄跟随其最新副本 |
| `wayrun.sqlite.query(handle, sql, params?)` | 行以表返回；NULL 列读作缺失 |
| `wayrun.kv.get(key)` | 取回存的字符串；缺失或已过期则为 nil |
| `wayrun.kv.set(key, value, ttl_secs?)` | 在 `key` 下存一个字符串；给了 ttl 会过期；库是插件自己目录里的一个 sqlite |
| `wayrun.kv.delete(key)` | 删掉一个键 |
| `wayrun.kv.keys(prefix?)` / `wayrun.kv.pairs(prefix?)` | 前缀下未过期的键（或 `{key, value}` 记录），按 key 排序 |
| `wayrun.fuzzy.match(query, candidates)` | 对字符串数组返回 `{index, kind}` 命中，最优在前；kind 就是启动器自己的匹配词汇（exact、prefix、word、substring、loose） |

`http.get` 带 `ttl` 时，重复调用由插件自己的存储应答而不是网络——只缓存 2xx 的
文本响应，这正是"每击键一次查询"能负担得起的原因。返回的 body 是原始字节，响应头
名小写；超时默认两秒，并被钳在宿主调用自身的上限之内，因此慢端点会抛出可被
`pcall` 的错误，而不是以"宿主被杀"告终。

## 沙箱

`os`、`io`、`package`、`load` 与 `print` 均不可达：脚本起不了进程，唯一的写是
`kv`（键不是路径，库落在插件自己的目录里）。能读的比这宽：`fs.read` 是受范围约束
的那一个（只收相对路径，限定在 `~/.config/wayrun/plugins/<id>/` 之内），而
`fs.list` 与 `fs.stat` 可对任意路径取名字与元数据，`sqlite.snapshot` 可把任意
SQLite 文件拷为副本整体查询（`firefox.lua` 就是这样读 `places.sqlite` 的），
`wayrun.env` 只能读调用中的插件自己声明的那些名字，`http` 可访问网络。沙箱约束的是脚本能做
什么，而不是能读什么。调用中抛错则本次返回空行并记录到 journal，因此 `wayrun.log`
与对风险操作的 `pcall` 就是调试手段。

## 限制

- Lua 插件必须有非空 keyword：它只应答自己的路由查询。默认链（keyword 为
  `""`）保留给内置插件。
- 行序即脚本返回的顺序；没有相关度通道。
- 图标必须是绝对路径；用 `wayrun.icon` 获取。

## 注册

复制 `template.lua`，保留 shebang 与执行位（`chmod +x`），像任何主机一样注册——
单个可执行文件 token：

```toml
[[plugins]]
id = "my-plugin"          # 必须与脚本返回的插件 id 一致
keyword = "mp"
command = "/absolute/path/to/my-plugin.lua"
resident = true           # 跨调用保留主机进程
```

脚本首行必须是 `#!/usr/bin/env -S wayrun --lua-host`。`example/lua/firefox.lua` 与
`example/lua/web.lua` 是两个完整示例，分别读取 `places.sqlite` 与网页。
