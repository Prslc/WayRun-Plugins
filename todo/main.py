#!/usr/bin/env python3
"""Todo plugin: a complete task manager.

Demonstrates @plugin.search, @plugin.default_view, a forget handler, and
state changes that re-invoke this script through a `run` command (so state
lives in a file and nothing depends on the core staying alive).

Data: ~/.config/wayrun/todo.json
Usage: type "todo", then space for all todos; keep typing to filter or add;
Enter toggles done; Backspace deletes the selected todo.
"""

import contextlib
import json
import os
import shlex
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wayrun_plugin import Item, plugin, run

# Bundled icon (absolute path; the UI renders file://).
ICON = str(Path(__file__).resolve().with_name("icon.svg"))
DATA_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wayrun"
DATA_PATH = DATA_DIR / "todo.json"

# A `run` command goes through a shell, so quote the path.
THIS_PATH = str(Path(__file__).resolve())
THIS = shlex.quote(THIS_PATH)


def load() -> dict[str, Any] | None:
    """Read the todo store; a missing file is empty, a broken one is None."""
    if not DATA_PATH.exists():
        return {"next_id": 1, "items": []}
    try:
        with DATA_PATH.open(encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    data.setdefault("next_id", max((it["id"] for it in data["items"]), default=0) + 1)
    return data


def save(data: dict[str, Any]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = DATA_PATH.with_suffix(".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    tmp.replace(DATA_PATH)  # atomic, so a partial write cannot corrupt the file


def broken_item() -> Item:
    return Item(
        title="Corrupt todo data", summary=f"Cannot read {DATA_PATH}; delete it"
    )


def row(item: dict[str, Any]) -> Item:
    """A todo row; Enter toggles its state."""
    action = run(f"{THIS} toggle {item['id']}")
    if item["done"]:
        return Item(title=item["text"], summary="Done · Enter reopens", on_click=action)
    return Item(title=item["text"], summary="Open · Enter marks done", on_click=action)


@plugin.search(
    id="todo",
    name="Todo",
    keyword="todo",  # must match the plugins.toml keyword
    icon=ICON,
    description="Manage todos: type to add, Enter toggles",
)
def search(text: str) -> list[Item]:
    data = load()
    if data is None:
        return [broken_item()]
    query = text.strip().lower()
    matches = [it for it in data["items"] if query in it["text"].lower()]
    if matches:
        return [row(it) for it in matches]
    # No match: offer to add the input as a new todo.
    action = run(f"{THIS} add {shlex.quote(text)}")
    return [Item(title=f'Add "{text}"', summary="Enter adds it", on_click=action)]


@plugin.default_view
def top() -> list[Item]:
    """All todos, open ones first."""
    data = load()
    if data is None:
        return [broken_item()]
    items = sorted(data["items"], key=lambda it: (it["done"], it["id"]))
    return [row(it) for it in items]


@plugin.method("forget")
def forget(params: object) -> None:
    """Delete the todo whose on_click command this forgotten row carries."""
    if not isinstance(params, dict):
        return
    on_click = params.get("on_click")
    if not isinstance(on_click, dict) or on_click.get("type") != "run":
        return
    cmd = on_click.get("cmd")
    if not isinstance(cmd, str):
        return
    parts = shlex.split(cmd)
    if len(parts) == 3 and parts[0] == THIS_PATH and parts[1] == "toggle":
        with contextlib.suppress(ValueError):
            cli_delete(int(parts[2]))


def cli_add(text: str) -> None:
    data = load()
    if data is None:
        return  # never write over a corrupt file
    data["items"].append({"id": data["next_id"], "text": text, "done": False})
    data["next_id"] += 1
    save(data)


def cli_toggle(todo_id: int) -> None:
    data = load()
    if data is None:
        return
    for it in data["items"]:
        if it["id"] == todo_id:
            it["done"] = not it["done"]
            save(data)
            return


def cli_delete(todo_id: int) -> None:
    data = load()
    if data is None:
        return
    kept = [it for it in data["items"] if it["id"] != todo_id]
    if len(kept) == len(data["items"]):
        return
    data["items"] = kept
    save(data)


def main() -> None:
    if len(sys.argv) < 2:
        plugin.run()  # started by the core: serve the JSON-RPC loop
        return
    action, *args = sys.argv[1:]  # started by a run command: apply a change
    if action == "add" and args:
        cli_add(" ".join(args))
    elif action == "toggle" and args:
        with contextlib.suppress(ValueError):
            cli_toggle(int(args[0]))


if __name__ == "__main__":
    main()
