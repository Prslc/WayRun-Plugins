"""Result rows and the helpers that build their ``on_click`` commands."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

# One wire command, ``{"type": ..., ...}``; see the WayRun protocol docs.
Command = dict[str, Any]


@dataclass
class Item:
    """One search-result row.

    ``title`` is required; the rest default to "not set". The four protocol
    keys are always emitted on the wire, with ``ephemeral`` only when set.
    An unset ``icon`` falls back to the plugin icon.

    ``ephemeral=True`` asks the core not to record this row in usage history,
    for a one-shot hit whose target is not worth re-opening later.
    """

    title: str
    summary: str | None = None
    on_click: Command | None = None
    icon: str | None = None
    ephemeral: bool = False

    def as_dict(self, default_icon: str | None = None) -> dict[str, Any]:
        """The wire form for this row, with the plugin icon as fallback."""
        item: dict[str, Any] = {
            "title": self.title,
            "summary": self.summary,
            "on_click": self.on_click,
            "icon": self.icon if self.icon is not None else default_icon,
        }
        if self.ephemeral:
            item["ephemeral"] = True
        return item


def run(cmd: str) -> Command:
    """A command that runs ``cmd`` through a shell."""
    return {"type": "run", "cmd": cmd}


def open_uri(uri: str) -> Command:
    """A command that opens ``uri`` with the default handler (URL/file/mailto)."""
    return {"type": "open", "uri": uri}


def copy_text(text: str) -> Command:
    """A command that writes ``text`` to the Wayland clipboard."""
    return {"type": "copy", "text": text}


def launch(desktop_id: str) -> Command:
    """A command that launches an app by desktop id."""
    return {"type": "launch", "desktop_id": desktop_id}


def desktop_action(desktop_id: str, action_id: str) -> Command:
    """A command that runs one ``[Desktop Action …]`` group of a desktop file."""
    return {"type": "desktop_action", "desktop_id": desktop_id, "action_id": action_id}


def reveal(uri: str) -> Command:
    """A command that shows a file in the file manager (panel-only)."""
    return {"type": "reveal", "uri": uri}


def terminal(uri: str) -> Command:
    """A command that opens a terminal in the URI's directory (panel-only)."""
    return {"type": "terminal", "uri": uri}


def hint(title: str, detail: str | None = None) -> Item:
    """A display-only row for usage or argument-error guidance."""
    return Item(title=title, summary=detail)


def split_command(text: str) -> tuple[str, str]:
    """Split ``"verb rest"`` into ``(verb, rest)``.

    The verb is lowercased for case-insensitive routing; the payload keeps
    its internal whitespace and is stripped at the edges. A bare verb yields
    an empty payload.
    """
    parts = text.split(maxsplit=1)
    verb = parts[0].lower() if parts else ""
    payload = parts[1].strip() if len(parts) > 1 else ""
    return verb, payload
