"""The JSON-RPC 2.0 loop that answers the core on stdin/stdout."""

from __future__ import annotations

import inspect
import json
import sys
from collections.abc import Callable
from typing import Any, Protocol

from ._item import Item


class PluginLike(Protocol):
    """What the server needs from a plugin registry; implemented by ``Plugin``."""

    @property
    def meta(self) -> dict[str, Any]: ...

    @property
    def handlers(self) -> dict[str, Callable[..., Any]]: ...


def _error(id_: Any, code: int, message: str) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "error": {"code": code, "message": message}, "id": id_}


def _result(id_: Any, result: Any) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "result": result, "id": id_}


def _wants_params(handler: Callable[..., Any]) -> bool:
    """Whether to pass the request params, from the handler's signature."""
    positional = (
        inspect.Parameter.POSITIONAL_ONLY,
        inspect.Parameter.POSITIONAL_OR_KEYWORD,
    )
    return any(
        p.kind in positional for p in inspect.signature(handler).parameters.values()
    )


class Server:
    """Validates one request line and dispatches it to a Plugin."""

    def __init__(self, plugin: PluginLike) -> None:
        self._plugin: PluginLike = plugin

    def handle(self, line: str) -> dict[str, Any] | None:
        """The response for one request line, or None for a notification."""
        try:
            msg = json.loads(line)
        except ValueError:
            return _error(None, -32600, "Invalid Request")
        if (
            not isinstance(msg, dict)
            or msg.get("jsonrpc") != "2.0"
            or not isinstance(msg.get("method"), str)
        ):
            return _error(None, -32600, "Invalid Request")
        if "id" not in msg:
            return None  # notification: side effect only, no response
        mid, method, params = msg["id"], msg["method"], msg.get("params")

        if method == "ping":
            return _result(mid, "pong")
        if method == "list_plugins":
            return _result(mid, [self._plugin.meta])
        if method == "search":
            return self._search(mid, params)

        handler = self._plugin.handlers.get(method)
        if handler is None:
            return _error(mid, -32601, "Method not found")
        try:
            result = handler(params) if _wants_params(handler) else handler()
        except Exception as exc:
            return _error(mid, -32603, str(exc))
        return _result(mid, self._normalize(result))

    def _normalize(self, result: Any) -> Any:
        """Item results become rows; any other value is returned raw."""
        if isinstance(result, Item):
            return self._rows(result)
        if isinstance(result, list) and any(isinstance(x, Item) for x in result):
            return self._rows(result)
        return result

    def _search(self, mid: Any, params: Any) -> dict[str, Any]:
        if not isinstance(params, dict):
            return _error(mid, -32602, "Invalid params")
        if params.get("plugin") not in (None, self._plugin.meta.get("id")):
            return _error(mid, -32602, "Unknown plugin")
        text = params.get("text")
        if not isinstance(text, str) or not text.strip():
            return _error(mid, -32602, "Invalid params")
        try:
            items = self._plugin.handlers["search"](text)
        except Exception as exc:
            items = [Item(title="Search failed", summary=str(exc))]
        return _result(mid, self._rows(items))

    def _rows(self, items: Any) -> list[dict[str, Any]]:
        """Normalize Item(s) or plain dict(s) into wire rows."""
        if isinstance(items, (Item, dict)):
            items = [items]
        default_icon = self._plugin.meta.get("icon")
        rows: list[dict[str, Any]] = []
        for item in items:
            if isinstance(item, dict):
                item = Item(
                    item.get("title", ""),
                    item.get("summary"),
                    item.get("on_click"),
                    item.get("icon"),
                )
            rows.append(item.as_dict(default_icon))
        return rows


def serve(plugin: PluginLike) -> None:
    """Read requests from stdin, write responses to stdout, exit on EOF."""
    server = Server(plugin)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        response = server.handle(line)
        if response is not None:
            sys.stdout.write(json.dumps(response, ensure_ascii=False) + "\n")
            sys.stdout.flush()
