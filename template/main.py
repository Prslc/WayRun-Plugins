#!/usr/bin/env python3
"""WayRun plugin skeleton.

Create a new plugin by copying this directory and editing this file:

    cp -r template my-plugin

Then register it in ~/.config/wayrun/plugins.toml (command must be a
single executable token; chmod +x main.py and use an absolute path):

    [[plugins]]
    id = "my-plugin"
    keyword = "mp"
    command = "/absolute/path/to/my-plugin/main.py"
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wayrun_plugin import Item, copy_text, hint, plugin

# Bundled icon (absolute path; the UI renders file://). Ship an icon file beside
# main.py and point at it; the core resolves no theme name or `papirus:` spec.
ICON = str(Path(__file__).resolve().with_name("icon.svg"))


@plugin.search(
    id="template",  # must match the plugins.toml entry id
    name="Template",
    keyword="tmp",
    icon=ICON,
    description="Example plugin skeleton",
)
def search(text: str) -> list[Item | dict[str, str]]:
    """Turn the query text into result items."""
    return [
        Item(
            title=f"You searched: {text}",
            summary="First result; Enter copies the text",
            on_click=copy_text(text),
        ),
        Item(title="Second result", summary="Display-only item"),
        {
            "title": "Plain dicts work too",
            "summary": "icon falls back to the plugin icon",
        },
    ]


@plugin.default_view
def top() -> list[Item]:
    """Guidance shown when the plugin is opened with an empty query."""
    return [hint("Type anything to search", "Enter copies your text")]


plugin.run()
