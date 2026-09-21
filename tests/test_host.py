"""Contract tests for the wayrun_plugin JSON-RPC host."""

import unittest
from typing import Any

from wayrun_plugin import (
    Item,
    Plugin,
    Server,
    copy_text,
    desktop_action,
    hint,
    launch,
    open_uri,
    reveal,
    run,
    split_command,
    terminal,
)


def make_plugin() -> Plugin:
    p = Plugin()

    @p.search(
        id="test",
        name="Test",
        keyword="t",
        icon="/opt/plugin/icon.svg",
        description="d",
    )
    def search(text: str) -> list[Item | dict[str, Any]]:
        return [
            Item(title=text),
            {"title": "dict row", "summary": "s", "on_click": run("true")},
        ]

    @p.method("echo")
    def echo(params: object) -> dict[str, object]:
        return {"got": params}

    @p.method("boom")
    def boom(_params: object) -> None:
        raise RuntimeError("kaboom")

    @p.method("items")
    def items(_params: object) -> list[Item]:
        return [Item(title="a"), Item(title="b", icon="/opt/plugin/x.svg")]

    return p


class ServerTest(unittest.TestCase):
    server: Server

    def setUp(self) -> None:
        self.server = Server(make_plugin())

    def req(self, line: str) -> dict[str, Any]:
        resp = self.server.handle(line)
        if resp is None:
            self.fail(f"no response for {line}")
        return resp

    def test_ping(self) -> None:
        self.assertEqual(
            self.req('{"jsonrpc":"2.0","method":"ping","id":1}'),
            {"jsonrpc": "2.0", "result": "pong", "id": 1},
        )

    def test_list_plugins_identity(self) -> None:
        resp = self.req('{"jsonrpc":"2.0","method":"list_plugins","id":2}')
        self.assertEqual(
            resp["result"],
            [
                {
                    "id": "test",
                    "name": "Test",
                    "keyword": "t",
                    "icon": "/opt/plugin/icon.svg",
                    "description": "d",
                    "enabled": True,
                }
            ],
        )

    def test_search_normalizes_items(self) -> None:
        resp = self.req(
            '{"jsonrpc":"2.0","method":"search","params":{"text":"hello"},"id":3}'
        )
        rows = resp["result"]
        self.assertEqual(rows[0]["title"], "hello")
        self.assertEqual(rows[0]["icon"], "/opt/plugin/icon.svg")  # Item icon fallback
        self.assertEqual(rows[1]["title"], "dict row")  # plain dict accepted
        self.assertEqual(rows[1]["icon"], "/opt/plugin/icon.svg")  # dict icon fallback
        for row in rows:  # all four keys present
            self.assertEqual(set(row), {"title", "summary", "on_click", "icon"})

    def test_search_plugin_param_must_match(self) -> None:
        ok = self.req(
            '{"jsonrpc":"2.0","method":"search",'
            '"params":{"plugin":"test","text":"x"},"id":4}'
        )
        self.assertNotIn("error", ok)
        bad = self.req(
            '{"jsonrpc":"2.0","method":"search",'
            '"params":{"plugin":"other","text":"x"},"id":5}'
        )
        self.assertEqual(bad["error"]["code"], -32602)

    def test_search_invalid_params(self) -> None:
        for line in (
            '{"jsonrpc":"2.0","method":"search","params":{"text":""},"id":6}',
            '{"jsonrpc":"2.0","method":"search","params":{"query":"x"},"id":7}',
            '{"jsonrpc":"2.0","method":"search","params":"x","id":8}',
            '{"jsonrpc":"2.0","method":"search","id":9}',
        ):
            self.assertEqual(self.req(line)["error"]["code"], -32602, line)

    def test_notification_gets_no_response(self) -> None:
        self.assertIsNone(self.server.handle('{"jsonrpc":"2.0","method":"ping"}'))

    def test_malformed_requests(self) -> None:
        for line in (
            "not json",
            "[]",
            '{"method":"ping","id":1}',
            '{"jsonrpc":"1.0","method":"ping","id":1}',
        ):
            self.assertEqual(self.req(line)["error"]["code"], -32600, line)

    def test_unknown_method(self) -> None:
        resp = self.req('{"jsonrpc":"2.0","method":"nope","id":10}')
        self.assertEqual(resp["error"]["code"], -32601)

    def test_custom_method_raw_data_passes_through(self) -> None:
        resp = self.req('{"jsonrpc":"2.0","method":"echo","params":[1,2],"id":11}')
        self.assertEqual(resp["result"], {"got": [1, 2]})

    def test_custom_method_items_are_normalized(self) -> None:
        resp = self.req('{"jsonrpc":"2.0","method":"items","id":15}')
        rows = resp["result"]
        self.assertEqual([r["title"] for r in rows], ["a", "b"])
        self.assertEqual(rows[0]["icon"], "/opt/plugin/icon.svg")  # fallback
        self.assertEqual(rows[1]["icon"], "/opt/plugin/x.svg")  # explicit kept

    def test_custom_method_error_is_internal_error(self) -> None:
        resp = self.req('{"jsonrpc":"2.0","method":"boom","id":12}')
        self.assertEqual(resp["error"]["code"], -32603)
        self.assertEqual(resp["error"]["message"], "kaboom")

    def test_default_view_is_served_without_params(self) -> None:
        p = Plugin()

        @p.search(
            id="dv",
            name="DV",
            keyword="dv",
            icon="/opt/plugin/dv.svg",
            description="default view test",
        )
        def search(_text: str) -> list[Item]:
            return []

        @p.default_view
        def top() -> list[Item]:
            return [
                Item(title="dv row"),
                Item(title="dv icon", icon="/opt/plugin/x.svg"),
            ]

        resp = Server(p).handle(
            '{"jsonrpc":"2.0","method":"top","params":{"plugin":"dv"},"id":16}'
        )
        assert resp is not None
        self.assertEqual([r["title"] for r in resp["result"]], ["dv row", "dv icon"])
        self.assertEqual(resp["result"][0]["icon"], "/opt/plugin/dv.svg")  # fallback
        self.assertEqual(resp["result"][1]["icon"], "/opt/plugin/x.svg")  # explicit

    def test_no_param_method_is_called_without_args(self) -> None:
        p = Plugin()

        @p.search(id="noargs")
        def search(_text: str) -> list[Item]:
            return []

        @p.method("now")
        def now() -> dict[str, bool]:
            return {"ok": True}

        resp = Server(p).handle('{"jsonrpc":"2.0","method":"now","id":17}')
        assert resp is not None
        self.assertEqual(resp["result"], {"ok": True})

    def test_search_handler_error_becomes_item(self) -> None:
        p = Plugin()

        @p.search(id="boom")
        def search(_text: str) -> list[Item]:
            raise RuntimeError("broken")

        resp = Server(p).handle(
            '{"jsonrpc":"2.0","method":"search","params":{"text":"x"},"id":13}'
        )
        assert resp is not None
        self.assertEqual(resp["result"][0]["title"], "Search failed")
        self.assertEqual(resp["result"][0]["summary"], "broken")

    def test_single_item_is_wrapped(self) -> None:
        p = Plugin()

        @p.search(id="single")
        def search(_text: str) -> Item:
            return Item(title="one")

        resp = Server(p).handle(
            '{"jsonrpc":"2.0","method":"search","params":{"text":"x"},"id":14}'
        )
        assert resp is not None
        self.assertEqual([r["title"] for r in resp["result"]], ["one"])

    def test_copy_text_roundtrip(self) -> None:
        text = 'say "hi"\ncafé'
        self.assertEqual(copy_text(text), {"type": "copy", "text": text})

    def test_command_builders_emit_structured_commands(self) -> None:
        self.assertEqual(run("ls -a"), {"type": "run", "cmd": "ls -a"})
        self.assertEqual(
            open_uri("https://example.com"),
            {"type": "open", "uri": "https://example.com"},
        )
        self.assertEqual(
            launch("firefox.desktop"),
            {"type": "launch", "desktop_id": "firefox.desktop"},
        )
        self.assertEqual(
            desktop_action("firefox.desktop", "new-window"),
            {
                "type": "desktop_action",
                "desktop_id": "firefox.desktop",
                "action_id": "new-window",
            },
        )
        self.assertEqual(
            reveal("file:///tmp/a"), {"type": "reveal", "uri": "file:///tmp/a"}
        )
        self.assertEqual(
            terminal("file:///tmp/a"), {"type": "terminal", "uri": "file:///tmp/a"}
        )


class HelperTest(unittest.TestCase):
    """Contract tests for the hint / split_command helpers."""

    def test_hint_builds_noninteractive_item(self) -> None:
        row = hint("missing content", "usage: x <a>")
        self.assertEqual(row.title, "missing content")
        self.assertEqual(row.summary, "usage: x <a>")
        self.assertIsNone(row.on_click)  # a guidance row is not Enter-able
        self.assertIsNone(row.icon)  # falls back to the plugin icon

    def test_hint_detail_is_optional(self) -> None:
        self.assertIsNone(hint("title only").summary)

    def test_split_command_basic(self) -> None:
        self.assertEqual(split_command("e hello café"), ("e", "hello café"))

    def test_split_command_case_insensitive_verb(self) -> None:
        self.assertEqual(split_command("D aGVsbG8="), ("d", "aGVsbG8="))

    def test_split_command_missing_payload(self) -> None:
        self.assertEqual(split_command("e"), ("e", ""))
        self.assertEqual(split_command("d   "), ("d", ""))

    def test_split_command_keeps_internal_spaces(self) -> None:
        self.assertEqual(split_command("e  a  b"), ("e", "a  b"))


class SubcommandPluginTest(unittest.TestCase):
    """A real search route built from hint + split_command, via Server."""

    def _plugin(self) -> Plugin:
        p = Plugin()

        @p.search(id="sub", name="Sub", icon="/opt/plugin/sub.svg", description="d")
        def search(text: str) -> list[Item]:
            verb, payload = split_command(text)
            if verb == "e":
                return [Item(title=f"enc:{payload}")]
            if verb == "d":
                return [Item(title=f"dec:{payload}")]
            return [hint("unknown", "usage")]

        return p

    def _search(self, text: str) -> list[dict[str, Any]]:
        resp = Server(self._plugin()).handle(
            f'{{"jsonrpc":"2.0","method":"search","params":{{"text":"{text}"}},"id":1}}'
        )
        assert resp is not None and "result" in resp
        return resp["result"]

    def test_routes_and_normalizes(self) -> None:
        rows = self._search("e x y")
        self.assertEqual(rows[0]["title"], "enc:x y")
        self.assertEqual(rows[0]["icon"], "/opt/plugin/sub.svg")  # plugin icon fallback

    def test_unknown_verb_yields_usage_row(self) -> None:
        rows = self._search("z q")
        self.assertEqual(rows[0]["title"], "unknown")
        self.assertEqual(rows[0]["summary"], "usage")
        self.assertIsNone(rows[0]["on_click"])


if __name__ == "__main__":
    unittest.main()
