#!/usr/bin/env python3
"""Todo plugin: a complete task manager.

Demonstrates @plugin.search, @plugin.default_view, a panel action, and state
changes that re-invoke this script through a `run` command (so state lives in
a file and nothing depends on the core staying alive).

Data: ~/.config/wayrun/todo.json
Usage: type "todo", then space for all todos; keep typing to filter or add;
Enter toggles done; Shift+Enter offers Delete.
"""

import contextlib
import json
import os
import shlex
import sys
from pathlib import Path
from typing import Any

from wayrun_plugin import Item, panel, plugin, run

# Bundled icon (absolute path; the UI renders file://).
ICON = str(Path(__file__).resolve().with_name("icon.svg"))
DATA_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wayrun"
DATA_PATH = DATA_DIR / "todo.json"

LOCALE = os.environ.get("WAYRUN_LOCALE", "en")
CATALOGS = {
    "en": {
        "name": "Todo",
        "description": "Manage todos: type to add, Enter toggles",
        "corrupt": "Corrupt todo data",
        "corrupt_summary": "Cannot read {path}; delete it",
        "delete": "Delete",
        "done": "Done · Enter reopens",
        "open": "Open · Enter marks done",
        "add": 'Add "{text}"',
        "add_summary": "Enter adds it",
    },
    "zh_cn": {
        "name": "待办",
        "description": "管理待办：输入即添加，Enter 切换完成",
        "corrupt": "待办数据损坏",
        "corrupt_summary": "无法读取 {path}；请删除它",
        "delete": "删除",
        "done": "已完成 · Enter 重新打开",
        "open": "未完成 · Enter 标记完成",
        "add": "添加「{text}」",
        "add_summary": "Enter 添加",
    },
}
STRINGS = CATALOGS.get(LOCALE, CATALOGS["en"])

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
        title=STRINGS["corrupt"],
        summary=STRINGS["corrupt_summary"].format(path=DATA_PATH),
    )


def row(item: dict[str, Any]) -> Item:
    """A todo row; Enter toggles its state, the panel offers Delete."""
    toggle = run(f"{THIS} toggle {item['id']}")
    # no id: deleting a todo stays out of the remembered-default reach
    delete = panel(STRINGS["delete"], run(f"{THIS} delete {item['id']}"))
    if item["done"]:
        return Item(
            title=item["text"],
            summary=STRINGS["done"],
            on_click=toggle,
            actions=[delete],
        )
    return Item(
        title=item["text"],
        summary=STRINGS["open"],
        on_click=toggle,
        actions=[delete],
    )


@plugin.search(
    id="todo",
    name=STRINGS["name"],
    keyword="todo",  # must match the plugins.toml keyword
    icon=ICON,
    description=STRINGS["description"],
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
    return [
        Item(
            title=STRINGS["add"].format(text=text),
            summary=STRINGS["add_summary"],
            on_click=action,
        )
    ]


@plugin.default_view
def top() -> list[Item]:
    """All todos, open ones first."""
    data = load()
    if data is None:
        return [broken_item()]
    items = sorted(data["items"], key=lambda it: (it["done"], it["id"]))
    return [row(it) for it in items]


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
    elif action == "delete" and args:
        with contextlib.suppress(ValueError):
            cli_delete(int(args[0]))


if __name__ == "__main__":
    main()
