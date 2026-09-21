#!/usr/bin/env python3
"""WayRun external plugin: Youdao translation over JSON-RPC 2.0.

The core spawns this host, relays `search`, and discovers the plugin's
identity from `list_plugins`. JSON-RPC plumbing lives in the shared
wayrun_plugin package; this file only declares the plugin.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from core.api import query_translate
from core.settings import load_settings

from wayrun_plugin import Item, copy_text, plugin

# Bundled icon (absolute path; the UI renders file://).
ICON = str(Path(__file__).resolve().with_name("icon.svg"))


@plugin.search(
    id="translate",
    name="Youdao Translation",
    keyword="tr",
    icon=ICON,
    description="Translate text via Youdao",
)
def search(text: str) -> list[Item]:
    cfg = load_settings()
    if cfg is None:
        return [
            Item(
                title="API credentials missing",
                summary=(
                    "Fill in app_token and app_secret in "
                    "~/.config/wayrun/translate.toml"
                ),
            )
        ]
    try:
        result = query_translate(text, cfg)
    except Exception as e:
        return [Item(title="Translation failed", summary=str(e))]
    if not result.strip():
        return [
            Item(
                title="Translation failed or returned empty result",
                summary=f"{cfg['lang_from_display']} -> {cfg['lang_to_display']}",
            )
        ]
    return [
        Item(
            title=result,
            summary=f"{cfg['lang_from_display']} -> {cfg['lang_to_display']}",
            on_click=copy_text(result),
        )
    ]


plugin.run()
