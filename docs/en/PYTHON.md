# Python plugins

The workspace's shared decorator framework, `wayrun_plugin`, owns the
stdin/stdout JSON-RPC 2.0 transport; a plugin is one directory with a `main.py`.

## Quick start

From the workspace root:

```sh
cp -r template my-plugin
# edit my-plugin/main.py
chmod +x my-plugin/main.py
```

Register it in `~/.config/wayrun/plugins.toml` (`command` is a single
executable token, so use an absolute path):

```toml
[[plugins]]
id = "my-plugin"          # must match the @plugin.search id
keyword = "mp"
command = "/absolute/path/my-plugin/main.py"
```

Minimal plugin:

```python
#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wayrun_plugin import plugin, Item, copy_text

# Ship an icon beside main.py; the core resolves no theme name.
ICON = str(Path(__file__).resolve().with_name("icon.svg"))


@plugin.search(
    id="my-plugin",  # must match the plugins.toml id
    name="My Plugin",
    keyword="mp",
    icon=ICON,  # absolute path to an icon the plugin ships
    description="Short description",
)
def search(text: str) -> list[Item]:
    return [Item(title=f"You searched: {text}", on_click=copy_text(text))]


plugin.run()
```

The bootstrap's `parents[N]` must reach the workspace root (the directory
holding `wayrun_plugin/`): `parents[1]` for a plugin directly under the root —
what `cp -r template` gives — and `parents[3]` for the shipped examples nested
at `example/python/<plugin>/`.

## API

### `@plugin.search(**meta)`

Registers the plugin identity (the `list_plugins` response) and the search
handler on `def search(text: str)`.

| Argument | Required | Meaning |
|----------|----------|---------|
| `id` | yes | plugin id; must match the `plugins.toml` entry |
| `name` | no | display name (falls back to the configured id) |
| `keyword` | no | trigger prefix (empty = a default provider) |
| `icon` | no | absolute path to an icon file the plugin ships |
| `description` | no | readiness hint text |

### `@plugin.method(name)`

Registers an extra JSON-RPC method. A handler that declares a parameter
receives the request `params`; a zero-argument handler is called with none.
An exception returns `-32603`. Returning `Item` (or a list containing one)
produces result rows with the same normalization as `search` (all keys
present, icon fallback); any other value is serialized as `result` as-is.

### `@plugin.default_view`

Registers the plugin's **default view**: the core calls it as the `top`
request when the plugin is opened with its keyword and an empty query, and
shows the rows it returns (protocol: WayRun `docs/en/jsonrpc.md`). A
zero-argument handler; normalization matches `search`:

```python
from wayrun_plugin import Item, plugin, run


@plugin.default_view
def top() -> list[Item]:
    return [
        Item(
            title="Buy milk",
            summary="Open - Enter marks done",
            on_click=run("todo toggle 1"),
        )
    ]
```

A plugin with no default view still shows its identity card (`name` +
`description`) when opened.

### `Item`

One result row. The four protocol keys (`title`, `summary`, `on_click`,
`icon`) are always emitted (unset ones as `null`); `ephemeral` is added only
when set. An unset `icon` falls back to the plugin icon, so most rows need no
per-row icon.

```python
Item(
    title="Title",
    summary="Secondary line",
    on_click=run("xdg-open ..."),
    icon=str(Path(__file__).resolve().with_name("row.svg")),
)
```

`ephemeral=True` asks the core not to record the row in usage history. Use it
for one-shot hits whose target is not worth re-opening later (the GitHub
example in `example/python/github/` marks its repository results this way).

### Icons

An external host owns its icons: the WayRun core resolves no theme icon name, no
`papirus:` spec and no `builtin:` glyph for a plugin. Ship the icon file inside
the plugin directory and pass its **absolute path** — that is what the core
renders (`file://` + path). `Path(__file__).resolve().with_name(...)` is the
portable way to build it.

`icon` is the plugin identity (the `?` list and the keyword hint) and the
per-row fallback; a row's own `icon` overrides it. A missing or non-absolute
icon falls back to the core's built-in placeholder.

### Command builders

`on_click` is a typed command object (`{"type": ..., ...}`), not a scheme
string. The helpers build one; import them from `wayrun_plugin`:

| Helper | Command |
|--------|---------|
| `run(cmd)` | run `cmd` through a shell |
| `run_in_terminal(cmd)` | run `cmd` in a terminal emulator (for a tty-bound binary) |
| `open_uri(uri)` | open a URL / `file:` / `mailto:` URI with the default handler |
| `copy_text(text)` | write `text` to the Wayland clipboard |
| `launch(desktop_id)` | launch an app by desktop id |
| `desktop_action(desktop_id, action_id)` | run one `[Desktop Action …]` group |
| `reveal(uri)` | show a file in the file manager (panel-only) |
| `terminal(uri)` | open a terminal in the URI's directory, its parent for a file (panel-only) |

A row without `on_click` is display-only. The wire shape is the `Command`
object documented in the WayRun `docs/en/jsonrpc.md`.

### `copy_text(text)`

Builds the command that writes `text` to the Wayland clipboard (quotes and
newlines are safe): `{"type": "copy", "text": "..."}`.

### `hint(title, detail=None)`

A non-interactive guidance row (no `on_click`, so Enter does nothing; `icon`
falls back to the plugin icon). `title` is the main line, `detail` the
secondary one. Useful for argument errors, progressive hints, and
`@plugin.default_view` usage rows.

```python
return [hint("Invalid amount: 'abc'", "e.g. cc 100 usd cny")]
```

### `split_command(text) -> (verb, payload)`

Splits a subcommand query: `"e hello world"` -> `("e", "hello world")`; a
bare verb gives an empty payload. The verb is lowercased (routing is
case-insensitive); the payload keeps its internal whitespace. Multi-word
positional routing (like the cc plugin) just uses `text.split()`.

### `plugin.run()`

The last line of `main.py`. Blocks reading stdin until EOF, answering `ping`,
`list_plugins`, `search`, `top`, and every registered method. A request
without an `id` is a notification and produces no response.

The loop serves until EOF, so the same host works both ways: forked per call
(one request, stdin closes) and, with `resident = true` in `plugins.toml`,
kept warm across calls — about 0.1ms per call instead of the ~40ms a fresh
interpreter costs.

### `Plugin`, `Server`, `serve` (advanced)

`plugin` is a module-level `Plugin()` for the usual one-process-one-plugin
case. For tests or embedding, build your own `Plugin`, register handlers on
it, and feed request lines to `Server(plugin).handle(line)`;
`serve(plugin)` runs the stdin loop that `plugin.run()` delegates to.

### Return values

A `search` handler may return:

- `list[Item]` / `list[dict]` — the usual case; a `dict` is normalized to an
  `Item` (missing fields become `null`, `icon` falls back to the plugin icon)
- a single `Item` / `dict` — wrapped into a one-element list

### Exceptions

- `search` raising yields a single error row (`title: "Search failed"`,
  `summary` the exception text), so the failure is visible in the launcher
  and the process does not crash. Catch it yourself for friendlier text.
- A custom method (`@plugin.method`) raising returns `-32603 Internal error`.
