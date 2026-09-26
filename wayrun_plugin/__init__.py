"""Public API for building a WayRun external plugin host.

A plugin is one ``main.py`` that registers its handlers and then calls
``plugin.run()``:

    from pathlib import Path

    from wayrun_plugin import plugin, Item, copy_text

    # Ship an icon beside main.py; the core resolves no theme name.
    ICON = str(Path(__file__).resolve().with_name("icon.svg"))

    @plugin.search(id="example", name="Example", keyword="ex",
                   icon=ICON, description="Demo plugin")
    def search(text: str) -> list[Item]:
        return [Item(title="Hello", on_click=copy_text(text))]

    plugin.run()

``plugin.run()`` serves the stdin/stdout JSON-RPC 2.0 loop. The wire protocol
is documented in the WayRun repository (``docs/en/jsonrpc.md``).
"""

from ._item import (
    Item,
    copy_text,
    desktop_action,
    hint,
    launch,
    open_uri,
    reveal,
    run,
    run_in_terminal,
    split_command,
    terminal,
)
from ._plugin import Plugin
from ._server import Server, serve

plugin = Plugin()

__version__ = "0.3.0"

__all__ = [
    "plugin",
    "Item",
    "copy_text",
    "desktop_action",
    "hint",
    "launch",
    "open_uri",
    "reveal",
    "run",
    "run_in_terminal",
    "split_command",
    "terminal",
    "Plugin",
    "Server",
    "serve",
]
