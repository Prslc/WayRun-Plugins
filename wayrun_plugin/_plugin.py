"""The decorator registry a plugin's ``main.py`` is built on."""

from __future__ import annotations

from collections.abc import Callable
from typing import Any, TypeVar

F = TypeVar("F", bound=Callable[..., Any])

# The plugin contract this framework targets. The core compares it against its
# own and logs a mismatch rather than refusing the plugin.
PLUGIN_API = 1


class Plugin:
    """Decorator registry for one external plugin process."""

    def __init__(self) -> None:
        self._meta: dict[str, Any] = {}
        self._handlers: dict[str, Callable[..., Any]] = {}

    @property
    def meta(self) -> dict[str, Any]:
        """The identity answered to ``list_plugins``."""
        return dict(self._meta)

    @property
    def handlers(self) -> dict[str, Callable[..., Any]]:
        """The registered method handlers by JSON-RPC method name."""
        return dict(self._handlers)

    def search(
        self,
        *,
        id: str,
        name: str = "",
        keyword: str = "",
        icon: str | None = None,
        description: str = "",
        api: int = PLUGIN_API,
    ) -> Callable[[F], F]:
        """Register the search handler and the plugin identity.

        ``id`` must match the ``plugins.toml`` entry, or the core ignores the
        identity. ``keyword`` empty means the plugin is a default provider.
        ``api`` is the plugin contract this was written against; it defaults to
        the one the framework targets and rarely needs stating.
        """

        def deco(fn: F) -> F:
            self._meta = {
                "id": id,
                "name": name,
                "keyword": keyword,
                "icon": icon,
                "description": description,
                "enabled": True,
                "api": api,
            }
            self._handlers["search"] = fn
            return fn

        return deco

    def method(self, name: str) -> Callable[[F], F]:
        """Register an extra JSON-RPC method.

        A handler declaring a parameter receives the request params; a
        zero-argument one is called without. Returning ``Item`` (or a list
        containing one) emits normalized rows; any other value is returned
        raw.
        """

        def deco(fn: F) -> F:
            self._handlers[name] = fn
            return fn

        return deco

    def default_view(self, fn: F) -> F:
        """Register the default view, served as the ``top`` method.

        Use it bare on a zero-argument handler. The core calls it when the
        plugin is opened with its keyword and an empty query.
        """
        self._handlers["top"] = fn
        return fn

    def run(self) -> None:
        """Serve stdin until EOF. The last line of ``main.py``."""
        from ._server import serve

        serve(self)
