# WayRun-Plugin

[WayRun](https://github.com/Prslc/WayRun) 的外部插件工作区：Python 插件走共享的
装饰器框架 `wayrun_plugin`，Lua 插件是单个脚本文件、由 WayRun 二进制本体承载。

English: [README.md](../../README.md)

## 目录结构

```
wayrun-plugin/
├── wayrun_plugin/          # 共享框架
│   ├── __init__.py         #   公共 API 与 __version__
│   ├── _item.py            #   Item、命令构造器、hint、split_command
│   ├── _plugin.py          #   Plugin（装饰器）
│   └── _server.py          #   Server / serve（JSON-RPC 循环）
├── template/               # cp -r template <新插件目录>；自带 icon.svg
├── template.lua            # Lua 插件骨架（单文件，见「Lua 插件」）
├── PYTHON.md               # Python 插件指南：快速开始、API 参考
├── LUA.md                  # Lua 插件指南：契约、wayrun 表、沙箱
├── tests/test_host.py      # 框架协议契约测试（unittest，无第三方依赖）
├── ruff.toml               # 代码风格配置
├── pyrightconfig.json      # LSP 配置
├── NOTICE                  # 内置图标署名（Material Symbols）
├── github/                 # 示例：GitHub 仓库搜索
├── todo/                   # 完整示范：待办管理
├── firefox.lua             # 示例：Firefox 书签与历史（Lua）
└── web.lua                 # 示例：搜索引擎联想词（Lua）
```

插件目录之间互不依赖，只共享根目录的 `wayrun_plugin` 包。每个插件的
`main.py` 通过 3 行 bootstrap 把工作区根加入 `sys.path`：

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
```

因此插件目录必须是工作区根的**直接子目录**。

## Python 插件

一个插件就是一个目录：复制 `template/`、编辑 `main.py`、在 `plugins.toml`
注册，传输层（stdin/stdout 的 JSON-RPC 2.0）交给框架。快速开始与完整 API
参考见 [PYTHON_CN.md](PYTHON_CN.md)。

## Lua 插件

插件也可以就是一个 Lua 脚本——无框架、无需安装 Python。WayRun 二进制自身承载
它（`wayrun --lua-host`），与 Python 主机讲同一套 JSON-RPC 接口，启动只需毫秒级。

脚本契约、完整的 `wayrun` 表、沙箱与注册见 [LUA_CN.md](LUA_CN.md)。本工作区的
`firefox.lua` 与 `web.lua` 是两个完整示例，分别读取 `places.sqlite` 与网页。

## 框架代管的协议行为

与 WayRun 后端约定的 JSON-RPC 2.0（完整协议见
[WayRun jsonrpc.md](https://github.com/Prslc/WayRun/blob/main/docs/zh_cn/jsonrpc.md)）：

| 情形 | 响应 |
|------|------|
| `ping` | `"pong"` |
| `list_plugins` | `[{id, name, keyword, icon, description, enabled}]` |
| `search` | 条目数组；`text` 非空字符串否则 `-32602`；`params.plugin` 若存在必须等于插件 id |
| `top` | 打开时的默认视图请求；结果项数组，未注册 `-32601` |
| `forget` | 后端把被移除行的 `on_click` 命令转发给对应主机；`null`，未注册 `-32601` |
| 无 `id` 的请求 | 无响应（notification） |
| JSON 无法解析 / 非对象 / `jsonrpc != "2.0"` / method 非字符串 | `-32600` |
| 未知方法 | `-32601` |

## 开发

```sh
python3 -m unittest discover -s tests   # 协议契约测试
uvx ruff check .                        # 静态检查
uvx ruff format .                       # 格式化
```

冒烟测试（模拟后端逐行喂入）：

```sh
printf '%s\n' '{"jsonrpc":"2.0","method":"search","params":{"text":"hello"},"id":1}' \
  | python3 my-plugin/main.py
```

## 部署注意

- **独立部署**：`wayrun_plugin` 包在工作区根。把插件复制出工作区时需让该包
  可导入：与插件同级放置一份 `wayrun_plugin/`，或 `pip install` 工作区。
- 修改 `@plugin.search` 的 `id` 时必须同步改 `plugins.toml`，否则后端忽略身份
  （插件仍可用，但 `?` 列表与 keyword 提示退化为默认占位）。
- 依赖仅标准库：`Item`/协议层零第三方依赖；各插件自行管理业务依赖
  （插件可自带 `requirements.txt` 声明额外依赖）。

## 许可证

WayRun-Plugin 采用双许可证，可任选其一：

- **MIT** —— [LICENSE-MIT](../../LICENSE-MIT)
- **Apache-2.0** —— [LICENSE-APACHE](../../LICENSE-APACHE)

内置插件图标为 Google Material Symbols，采用 Apache License 2.0；
署名与许可证全文见 [NOTICE](../../NOTICE)。
