#!/usr/bin/env python3
"""base64 encoder/decoder: routes on the first argument, Enter copies.

Usage (the core strips the keyword): base64 <e|d> <text>
- e encodes, d decodes; the payload is the rest of the query, internal
  spaces kept (split_command)
- a missing or invalid payload becomes a friendly hint row, never an exception
"""

import base64
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wayrun_plugin import Item, copy_text, hint, plugin, split_command

# Bundled icon (absolute path; the UI renders file://).
ICON = str(Path(__file__).resolve().with_name("icon.png"))

USAGE = "Usage: base64 <e|d> <text>"


@plugin.search(
    id="base64",
    name="base64",
    icon=ICON,
    description="Encode/decode: base64 <e|d> <text>",
)
def search(text: str) -> list[Item]:
    verb, payload = split_command(text)

    if verb == "e":
        if not payload:
            return [hint("Missing text to encode", USAGE)]
        encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
        return [
            Item(
                title=f"Encoded: {encoded}",
                summary="Enter copies the base64 result",
                on_click=copy_text(encoded),
            )
        ]

    if verb == "d":
        if not payload:
            return [hint("Missing text to decode", USAGE)]
        try:
            # validate=True rejects non-base64 characters and bad padding.
            decoded = base64.b64decode(payload.encode("ascii"), validate=True).decode(
                "utf-8"
            )
        except ValueError:
            return [hint(f"Cannot decode: '{payload}'", USAGE)]
        return [
            Item(
                title=f"Decoded: {decoded}",
                summary="Enter copies the decoded text",
                on_click=copy_text(decoded),
            )
        ]

    return [hint(f"Unknown verb: '{verb}'", USAGE)]


@plugin.default_view
def top() -> list[Item]:
    """Usage shown when base64 is opened with an empty query."""
    return [hint("base64 <e|d> <text>", "e encodes · d decodes")]


plugin.run()
