"""The golden wire corpus: one exact JSON shape per row and command feature.

The WayRun core pins the same corpus on its side (its `provider/external.rs`
test `every_command_variant_parses_from_a_host`); when the wire grows a
feature, both sides gain a case in the same change.
"""

from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path
from typing import Any

from wayrun_plugin import (
    Item,
    Server,
    copy_text,
    desktop_action,
    launch,
    open_uri,
    reveal,
    run,
    run_in_terminal,
    terminal,
)

ROWS: list[tuple[Item, str | None, dict[str, Any]]] = [
    (
        Item(title="title only"),
        None,
        {"title": "title only", "summary": None, "on_click": None, "icon": None},
    ),
    (
        Item(
            title="full",
            summary="s",
            on_click=open_uri("https://example.com"),
            icon="/opt/x.svg",
        ),
        None,
        {
            "title": "full",
            "summary": "s",
            "on_click": {"type": "open", "uri": "https://example.com"},
            "icon": "/opt/x.svg",
        },
    ),
    (
        Item(title="ephemeral", ephemeral=True),
        None,
        {
            "title": "ephemeral",
            "summary": None,
            "on_click": None,
            "icon": None,
            "ephemeral": True,
        },
    ),
    (
        Item(title="fallback"),
        "/opt/identity.svg",
        {
            "title": "fallback",
            "summary": None,
            "on_click": None,
            "icon": "/opt/identity.svg",
        },
    ),
]

COMMANDS: list[tuple[Any, dict[str, Any]]] = [
    (run("echo hi"), {"type": "run", "cmd": "echo hi"}),
    (run_in_terminal("htop"), {"type": "run_in_terminal", "cmd": "htop"}),
    (open_uri("https://example.com"), {"type": "open", "uri": "https://example.com"}),
    (copy_text("x"), {"type": "copy", "text": "x"}),
    (launch("firefox.desktop"), {"type": "launch", "desktop_id": "firefox.desktop"}),
    (
        desktop_action("firefox.desktop", "new-private-window"),
        {
            "type": "desktop_action",
            "desktop_id": "firefox.desktop",
            "action_id": "new-private-window",
        },
    ),
    (reveal("file:///home/u"), {"type": "reveal", "uri": "file:///home/u"}),
    (terminal("file:///home/u"), {"type": "terminal", "uri": "file:///home/u"}),
]


class GoldenWireTest(unittest.TestCase):
    def test_every_row_feature_serializes_to_the_golden_json(self) -> None:
        for item, default_icon, expected in ROWS:
            self.assertEqual(item.as_dict(default_icon), expected)

    def test_every_command_builder_serializes_to_the_golden_json(self) -> None:
        for built, expected in COMMANDS:
            self.assertEqual(built, expected)

    def test_a_search_reply_carries_the_golden_rows(self) -> None:
        server = Server(_SearchPlugin())
        response = server.handle(
            '{"jsonrpc":"2.0","method":"search",'
            '"params":{"plugin":"golden","text":"hi"},"id":1}'
        )
        assert response is not None
        rows = response["result"]
        self.assertEqual(
            rows[0],
            {
                "title": "You searched: hi",
                "summary": None,
                "on_click": {"type": "copy", "text": "hi"},
                "icon": "/opt/identity.svg",
            },
        )
        self.assertEqual(rows[1], ROWS[1][2])


class _SearchPlugin:
    """The two golden rows as one plugin, without the decorator machinery."""

    meta = {"id": "golden", "name": "Golden", "icon": "/opt/identity.svg"}

    @property
    def handlers(self) -> dict[str, Any]:
        def search(text: str) -> list[Item]:
            return [
                Item(title=f"You searched: {text}", on_click=copy_text(text)),
                ROWS[1][0],
            ]

        return {"search": search}


class TemplateServeLoopTest(unittest.TestCase):
    """The shipped template end to end: many requests, one process, EOF exits."""

    def test_the_template_serves_until_eof(self) -> None:
        template = Path(__file__).resolve().parents[1] / "template" / "main.py"
        requests = [
            json.dumps({"jsonrpc": "2.0", "method": "list_plugins", "id": 1}),
            json.dumps(
                {
                    "jsonrpc": "2.0",
                    "method": "search",
                    "params": {"plugin": "template", "text": "hi"},
                    "id": 2,
                }
            ),
        ]
        result = subprocess.run(
            [sys.executable, str(template)],
            input="\n".join(requests) + "\n",
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        replies = [json.loads(line) for line in result.stdout.splitlines()]
        self.assertEqual(len(replies), 2, "one process served both requests")
        self.assertEqual(replies[0]["result"][0]["id"], "template")
        row = replies[1]["result"][0]
        self.assertEqual(row["title"], "You searched: hi")
        self.assertEqual(row["on_click"], {"type": "copy", "text": "hi"})
