#!/usr/bin/env python3
import json
import sys
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wayrun_plugin import Item, hint, open_uri, plugin

ICON = str(Path(__file__).with_name("icon.png"))


@plugin.search(
    id="bilibili_search",
    name="Bilibili Search",
    keyword="bl",
    icon=ICON,
    description="fast search for bilibili",
)
def search(text: str) -> list[Item]:
    if not text.strip():
        return []

    url = "https://s.search.bilibili.com/main/suggest?" + urlencode({"term": text})
    req = Request(url, headers={"User-Agent": "Mozilla/5.0"})

    try:
        with urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        return [Item(title=f"Error: {e}", summary="Request failed")]

    tags = (data.get("result") or {}).get("tag") or []
    kws = [text] + [t["value"] for t in tags if t["value"] != text]
    return [
        Item(
            title=kw,
            summary="Bilibili Search" if kw == text else "Bilibili Search suggestion",
            on_click=open_uri(
                "https://search.bilibili.com/all?" + urlencode({"keyword": kw})
            ),
        )
        for kw in kws
    ]


@plugin.default_view
def top() -> list[Item]:
    return [hint("Type a keyword to search Bilibili", "Enter opens the results page")]


plugin.run()
