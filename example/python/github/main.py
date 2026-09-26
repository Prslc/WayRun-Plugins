#!/usr/bin/env python3
"""GitHub repository search plugin for WayRun."""

import json
import os
import sys
from pathlib import Path
from typing import Any
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from wayrun_plugin import Item, open_uri, plugin

# Bundled icon (absolute path; the UI renders file://).
ICON = str(Path(__file__).resolve().with_name("icon.svg"))
# Optional classic or fine-grained PAT; both authenticate as "Bearer". Without
# it the search API is limited to 10 req/min and 60 req/hr per IP.
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN", "")


def fetch_repos(query: str, token: str) -> dict[str, Any]:
    """Run the repository search, authenticating only when ``token`` is set."""
    headers = {"Accept": "application/vnd.github+json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = Request(
        f"https://api.github.com/search/repositories?{query}", headers=headers
    )
    # A stalled api.github.com must fail fast and visibly: the core gives a host
    # 5s and then kills it (the row would just be empty), while this raises
    # inside the plugin and the framework shows "Search failed: timed out".
    with urlopen(request, timeout=4) as response:
        return json.load(response)


@plugin.search(
    id="github",
    name="GitHub",
    icon=ICON,
    description="Search GitHub repositories",
)
def search(text: str) -> list[Item]:
    query = urlencode({"q": text, "per_page": 8})
    try:
        data = fetch_repos(query, GITHUB_TOKEN)
    except HTTPError as error:
        # A stale or revoked token must not break search: 401 answers fast, so
        # retrying anonymously stays inside the timeout budget, just at the
        # lower quota.
        if not GITHUB_TOKEN or error.code != 401:
            raise
        data = fetch_repos(query, "")
    return [
        Item(
            title=repo["full_name"],
            summary=repo.get("description"),
            on_click=open_uri(repo["html_url"]),
            icon=ICON,
            # a repo hit is a one-shot search result, not a target to re-open
            ephemeral=True,
        )
        for repo in data["items"]
    ]


plugin.run()
