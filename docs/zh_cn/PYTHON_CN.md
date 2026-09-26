# Python 插件

工作区的共享装饰器框架 `wayrun_plugin` 代管 stdin/stdout 的 JSON-RPC 2.0 传输；
一个插件就是一个带 `main.py` 的目录。

## 快速开始

```sh
cp -r template my-plugin
# 编辑 my-plugin/main.py
chmod +x my-plugin/main.py
```

在 `~/.config/wayrun/plugins.toml` 注册（`command` 是单个可执行令牌，用绝对路径）：

```toml
[[plugins]]
id = "my-plugin"          # 必须与 main.py 中 @plugin.search 的 id 一致
keyword = "mp"
command = "/absolute/path/my-plugin/main.py"
```

最小插件：

```python
#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wayrun_plugin import plugin, Item, copy_text

# 图标放在 main.py 同目录；后端不解析任何主题图标名。
ICON = str(Path(__file__).resolve().with_name("icon.svg"))


@plugin.search(
    id="my-plugin",  # 与 plugins.toml 的 id 一致
    name="My Plugin",
    keyword="mp",
    icon=ICON,  # 插件自带图标的绝对路径
    description="简短说明",
)
def search(text: str) -> list[Item]:
    return [Item(title=f"你搜了：{text}", on_click=copy_text(text))]


plugin.run()
```

## API 参考

### `@plugin.search(**meta)`

注册插件身份（`list_plugins` 响应）与搜索处理函数，装饰在
`def search(text: str)` 上。

| 参数 | 必填 | 含义 |
|------|------|------|
| `id` | 是 | 插件 id，必须与 `plugins.toml` 条目一致 |
| `name` | 否 | 显示名（空则回退为配置的 id） |
| `keyword` | 否 | 触发前缀（空 = 默认触发） |
| `icon` | 否 | 插件自带图标文件的绝对路径 |
| `description` | 否 | 就绪提示文案 |

### `@plugin.method(name)`

处理函数声明了参数则收到请求 `params`；零参数的处理函数则不传参调用。
方法抛异常返回 `-32603`。返回 `Item`（或含 `Item` 的列表）视为结果条目，
走与 `search` 相同的归一化（协议键全量、`icon` 回退）；其它返回值（如普通
dict）原样作为 `result` 序列化。

### `@plugin.default_view`

注册插件的**默认视图**——后端以关键词 + 空格打开插件（空查询）时，会向主机
发起 `top` 请求并展示返回的结果行（协议见
[WayRun jsonrpc.md](https://github.com/Prslc/WayRun/blob/main/docs/zh_cn/jsonrpc.md)）。
零参数处理函数，返回结果行，归一化与 `search` 相同：

```python
from wayrun_plugin import Item, plugin, run


@plugin.default_view
def top() -> list[Item]:
    return [
        Item(
            title="买牛奶",
            summary="待完成 · Enter 标记完成",
            on_click=run("todo toggle 1"),
        )
    ]
```

未注册默认视图的插件，打开时后端仍显示身份卡片（`name` + `description`）。

### `Item`

一条搜索结果。四个协议键（`title`/`summary`/`on_click`/`icon`）总是全量输出
（未设置者为 `null`）；`ephemeral` 仅在为真时输出。`icon` 为 `None` 时自动
回退到插件图标——多数插件无需逐条重复设置图标。

```python
Item(
    title="标题",
    summary="副行",
    on_click=run("xdg-open ..."),
    icon=str(Path(__file__).resolve().with_name("row.svg")),
)
```

`ephemeral=True` 要求后端不把该行记入使用历史，适合一次性的搜索命中（github
插件就是这么标记仓库结果的）。

### 图标

图标由外部主机自备：WayRun 后端**不**为主机解析主题图标名、`papirus:` 规格或
`builtin:` 字形。把图标文件放进插件目录，传它的**绝对路径**——后端就按
`file://` + 路径渲染。`Path(__file__).resolve().with_name(...)` 是可移植的构造方式。

`icon` 既是插件身份（`?` 列表与关键词提示），也是逐行回退值；行自身的 `icon`
覆盖它。图标缺失或不是绝对路径时，回退到后端内置的占位图标。

### 命令构造器

`on_click` 是带类型的命令对象（`{"type": ..., ...}`），不是 scheme 字符串。
以下构造器负责生成，直接从 `wayrun_plugin` 导入：

| 构造器 | 命令 |
|--------|------|
| `run(cmd)` | 通过 shell 执行 `cmd` |
| `run_in_terminal(cmd)` | 在终端模拟器中执行 `cmd`（需要 tty 的程序用） |
| `open_uri(uri)` | 用默认处理器打开 URL / `file:` / `mailto:` URI |
| `copy_text(text)` | 写入 Wayland 剪贴板 |
| `launch(desktop_id)` | 按 desktop id 启动应用 |
| `desktop_action(desktop_id, action_id)` | 运行一个 `[Desktop Action …]` 组 |
| `reveal(uri)` | 在文件管理器中定位文件（仅面板可见） |
| `terminal(uri)` | 在 URI 所在目录打开终端，文件则用其父目录（仅面板可见） |

不设置 `on_click` 的行仅展示。它的格式就是 WayRun `docs/zh_cn/jsonrpc.md`
里记录的 `Command` 对象。

### `copy_text(text)`

生成写入 Wayland 剪贴板的命令（引号和换行都安全）：
`{"type": "copy", "text": "..."}`。

### `hint(title, detail=None)`

构造**非交互引导行**（无 `on_click`，回车无动作；`icon` 交给插件图标回退）：
`title` 主文案、`detail` 副行。适合 search 的参数错误提示、渐进提示与
`@plugin.default_view` 的用法行。

```python
return [hint("金额无效：'abc'", "例：cc 100 usd cny")]
```

### `split_command(text) -> (verb, payload)`

子命令式查询拆分：`"e hello 世界"` → `("e", "hello 世界")`；仅有动词时 payload
为 `""`。verb 统一转小写（路由大小写不敏感），payload 去首尾空白、保留内部空格。
多词位置参数路由（cc）不需要它：`text.split()` 后按参数个数分支即可。

### `plugin.run()`

`main.py` 最后一行。阻塞读 stdin 直到 EOF：应答 `ping` / `list_plugins` /
`search` / `top` 与所有注册方法。无 `id` 的请求是 notification，不产生响应。

循环服务到 EOF，因此同一个主机两种用法皆可：逐次 fork（一个请求后 stdin 关闭），
或在 `plugins.toml` 中设 `resident = true` 后跨调用保温——每次调用约 0.1ms，
而每次新起解释器要约 40ms。

### `Plugin`、`Server`、`serve`（进阶）

`plugin` 是模块级的 `Plugin()` 单例，对应「一进程一插件」的常见写法。测试或内嵌
时，可自建 `Plugin` 注册处理函数，再把请求行喂给 `Server(plugin).handle(line)`；
`serve(plugin)` 就是 `plugin.run()` 委托的 stdin 循环。

### 返回值约定

`search` 处理函数可返回：

- `list[Item]` / `list[dict]` —— 常规；`dict` 会被归一化为 `Item`
  （缺省字段补 `null`，`icon` 同样回退到插件图标）
- 单个 `Item` / `dict` —— 自动包装成单元素列表

### 异常语义

- `search` 抛异常：框架捕获并返回一条错误结果条目
  （`title: "Search failed"`，`summary: 异常信息`），失败可见于启动器 UI，
  进程不崩溃。插件可用自己的 `try/except` 覆盖出更友好的文案。
- 自定义方法（`@plugin.method`）抛异常：返回 `-32603 Internal error`。
