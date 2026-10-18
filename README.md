# WayRun-Plugin

Plugin toolkit for [WayRun](https://github.com/Prslc/WayRun): Python plugins
through the shared decorator framework `wayrun_plugin`, Lua plugins as one entry
script (optionally split into modules) hosted by the WayRun binary.

The root promises the framework and the templates. `examples/` is read-only
reference material: nothing there is discovered or registered, and a plugin runs
only when your own `plugins.toml` names its command.

## Layout

```
wayrun-plugin/
├── wayrun_plugin/          # shared framework
│   ├── __init__.py         # public API + __version__
│   ├── _item.py            # Item, the command builders, hint, split_command
│   ├── _plugin.py          # Plugin (the decorators)
│   └── _server.py          # Server / serve (the JSON-RPC loop)
├── template/               # cp -r template <new-plugin>; ships icon.svg
├── lua/wayrun.lua          # LuaLS stub for the wayrun SDK
├── .luarc.json             # points LuaLS's workspace library at lua/
├── template.lua            # Lua plugin skeleton (one file)
├── examples/               # read-only worked examples
│   ├── python/
│   │   ├── github/         # GitHub repository search
│   │   └── todo/           # full example: todo manager
│   └── lua/
│       ├── firefox.lua     # Firefox bookmarks and history (one host)
│       ├── web.lua         # search-engine suggestions
│       ├── screenshots.lua # recent screenshots with image previews
│       └── documents.lua   # notes with text previews
│           documents/      # sample notes the plugin ships
├── docs/en/                # PYTHON.md
├── docs/zh_cn/             # README_CN.md, PYTHON_CN.md
├── tests/test_host.py      # framework protocol contract tests (unittest)
├── ruff.toml               # lint + format config
├── pyrightconfig.json      # LSP config
└── NOTICE                  # bundled-icon attribution (Material Symbols)
```

Plugins are independent of each other and only share the `wayrun_plugin`
package at the workspace root. Each `main.py` bootstraps it with three lines:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
```

so the bootstrap must reach the workspace root: `parents[1]` when the plugin
directory sits directly under the root (the layout `template/` ships),
`parents[3]` for the examples nested at `examples/python/<plugin>/`.

## Python plugins

A plugin is one directory: copy `template/`, edit `main.py`, register it in
`plugins.toml`, and the framework owns the stdin/stdout JSON-RPC 2.0 transport.
The quick start and the full API reference are in
[docs/en/PYTHON.md](docs/en/PYTHON.md); `examples/python/` holds the two worked
examples.

## Lua plugins

A plugin can also be Lua — one entry script, optionally split into modules with
`wayrun.import` — no framework, no Python install. The WayRun binary hosts it
itself (`wayrun --lua-host`), answering the same
JSON-RPC surface a Python host does, so it starts in milliseconds. Its guide —
the script contract, the full `wayrun` table, the sandbox and registration —
lives with the launcher that implements it:
[Lua plugins](https://github.com/Prslc/WayRun/blob/main/docs/en/lua.md).

`examples/lua/firefox.lua` (a host with two plugins) and `examples/lua/web.lua`
are complete worked examples, reading `places.sqlite` and the web respectively.
`examples/lua/screenshots.lua` and `examples/lua/documents.lua` show the split
preview column: recent images in `~/Pictures/Screenshots` and plain-text notes
shipped beside the script, each with open/copy/reveal actions.

The repo vendors the LuaLS stub at `lua/wayrun.lua`; `.luarc.json` points
`Lua.workspace.library` at it, so `wayrun.` completes in `template.lua` and the
examples. The stub is copied from WayRun's `lua/wayrun.lua`; refresh it when the
SDK changes.

Scripts can split into modules with `wayrun.import("lib/util")`, write under
their own directory with `wayrun.fs.write`, and debug with `print` or
`wayrun.log` — both go to the journal, never stdout.

## Protocol

The JSON-RPC 2.0 contract with the WayRun core (full protocol in WayRun
`docs/en/jsonrpc.md`):

| Case | Response |
|------|----------|
| `ping` | `"pong"` |
| `list_plugins` | `[{id, name, keyword, icon, description, enabled, api}]` |
| `search` | array of rows; `text` must be a non-empty string, else `-32602`; `params.plugin`, when present, must equal the plugin id |
| `top` | the default view request; rows, or `-32601` when unregistered |
| request without `id` | no response (notification) |
| unparseable / non-object / `jsonrpc != "2.0"` / non-string method | `-32600` |
| unknown method | `-32601` |

## Development

```sh
python3 -m unittest discover -s tests   # protocol contract tests
uvx ruff check .                        # lint
uvx ruff format .                       # format
```

Smoke-test a plugin by feeding it a request line:

```sh
printf '%s\n' '{"jsonrpc":"2.0","method":"search","params":{"text":"hello"},"id":1}' \
  | python3 my-plugin/main.py
```

## Deployment notes

- **Standalone deployment**: `wayrun_plugin` sits at the workspace root. When
  a plugin is copied out of the workspace, make the package importable — put a
  `wayrun_plugin/` beside it, or install the workspace with `pip`.
- Changing a `@plugin.search` `id` means changing `plugins.toml` too, or the
  core ignores the identity (the plugin still works, but the `?` list and the
  keyword hint fall back to a placeholder).
- Standard library only: `Item` and the protocol layer have no third-party
  dependencies. Each plugin manages its own (a plugin with extras can ship a
  `requirements.txt` of its own).

## License

Dual licensed under either of the following, at your option:

- **MIT** — [LICENSE-MIT](LICENSE-MIT)
- **Apache-2.0** — [LICENSE-APACHE](LICENSE-APACHE)

The bundled plugin icons are Google Material Symbols under the Apache License
2.0; see [NOTICE](NOTICE) for the attribution and the full license text.
