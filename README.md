# WayRun-Plugin

External plugin workspace for [WayRun](https://github.com/Prslc/WayRun): Python
plugins through the shared decorator framework `wayrun_plugin`, Lua plugins as
one script file hosted by the WayRun binary.

## Layout

```
wayrun-plugin/
├── wayrun_plugin/          # shared framework
│   ├── __init__.py         #   public API + __version__
│   ├── _item.py            #   Item, the command builders, hint, split_command
│   ├── _plugin.py          #   Plugin (the decorators)
│   └── _server.py          #   Server / serve (the JSON-RPC loop)
├── template/               # cp -r template <new-plugin>; ships icon.svg
├── template.lua            # Lua plugin skeleton (one file; see Lua plugins)
├── PYTHON.md               # Python plugin guide: quick start, API reference
├── LUA.md                  # Lua plugin guide: contract, wayrun table, sandbox
├── tests/test_host.py      # framework protocol contract tests (unittest)
├── ruff.toml               # lint + format config
├── pyrightconfig.json      # LSP config
├── NOTICE                  # bundled-icon attribution (Material Symbols)
├── github/                 # example: GitHub repository search
├── todo/                   # full example: todo manager
├── firefox.lua             # example: Firefox bookmarks and history, in Lua
└── web.lua                 # example: search-engine suggestions, in Lua
```

Plugins are independent of each other and only share the `wayrun_plugin`
package at the workspace root. Each `main.py` bootstraps it with three lines:

```python
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
```

so a plugin directory must be a direct child of the workspace root.

## Python plugins

A plugin is one directory: copy `template/`, edit `main.py`, register it in
`plugins.toml`, and the framework owns the stdin/stdout JSON-RPC 2.0 transport.
The quick start and the full API reference are in [PYTHON.md](PYTHON.md).

## Lua plugins

A plugin can also be one Lua script — no framework, no Python install. The
WayRun binary hosts it itself (`wayrun --lua-host`), answering the same
JSON-RPC surface a Python host does, so it starts in milliseconds.

[LUA.md](LUA.md) has the script contract, the full `wayrun` table, the sandbox
and registration. This workspace's `firefox.lua` and `web.lua` are complete
worked examples, reading `places.sqlite` and the web respectively.

## Protocol

The JSON-RPC 2.0 contract with the WayRun core (full protocol in WayRun
`docs/en/jsonrpc.md`):

| Case | Response |
|------|----------|
| `ping` | `"pong"` |
| `list_plugins` | `[{id, name, keyword, icon, description, enabled}]` |
| `search` | array of rows; `text` must be a non-empty string, else `-32602`; `params.plugin`, when present, must equal the plugin id |
| `top` | the default view request; rows, or `-32601` when unregistered |
| `forget` | core relays a forgotten row's `on_click` command; `null`, or `-32601` when unregistered |
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
