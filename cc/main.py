#!/usr/bin/env python3
"""cc currency converter: multi-argument routing example.

Usage: cc <amount> <from> <to>    e.g. cc 1 yun usd / cc 100 usd jpy

- search fires on every keystroke and hints progressively as arguments
  arrive (amount, then from, then to); the network is only touched once all
  three are present and valid
- currencies accept ISO 4217 codes and common aliases (yuan/rmb -> CNY,
  dollar -> USD, ...)
- rates come from open.er-api.com (daily, 160+ currencies) and are cached in
  ~/.config/wayrun/cc_rates.json (12h TTL), falling back to the stale cache
  when offline
- Enter copies the converted amount

The data directory matches the todo and translate plugins (~/.config/wayrun).
"""

import json
import os
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from wayrun_plugin import Item, copy_text, hint, plugin

# Bundled icon (absolute path; the UI renders file://). Shared by the plugin
# icon and the per-row fallback.
ICON = str(Path(__file__).with_name("icon.svg"))
DATA_DIR = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wayrun"
CACHE_PATH = DATA_DIR / "cc_rates.json"
TTL_SECONDS = 12 * 3600
RATES_URL = "https://open.er-api.com/v6/latest/USD"

# Common aliases -> ISO 4217. Any three-letter code is also accepted; it is
# validated against the rate table at conversion time.
ALIASES = {
    "usd": "USD",
    "dollar": "USD",
    "us": "USD",
    "cny": "CNY",
    "yuan": "CNY",
    "yun": "CNY",
    "rmb": "CNY",
    "renminbi": "CNY",
    "eur": "EUR",
    "euro": "EUR",
    "jpy": "JPY",
    "yen": "JPY",
    "gbp": "GBP",
    "pound": "GBP",
    "hkd": "HKD",
    "twd": "TWD",
    "nt": "TWD",
    "krw": "KRW",
    "won": "KRW",
    "aud": "AUD",
    "cad": "CAD",
    "chf": "CHF",
    "sgd": "SGD",
    "nzd": "NZD",
    "thb": "THB",
    "inr": "INR",
    "myr": "MYR",
    "idr": "IDR",
    "vnd": "VND",
    "php": "PHP",
    "sek": "SEK",
    "nok": "NOK",
    "brl": "BRL",
    "mxn": "MXN",
    "zar": "ZAR",
    "try": "TRY",
    "ils": "ILS",
}


def normalize(code: str) -> str | None:
    """An alias or three-letter code to ISO 4217, or None."""
    c = code.strip()
    if c.lower() in ALIASES:
        return ALIASES[c.lower()]
    if len(c) == 3 and c.isalpha():
        return c.upper()
    return None


def fetch_rates() -> dict[str, float] | None:
    """The USD-based rate table, or None when the request fails."""
    try:
        req = urllib.request.Request(RATES_URL, headers={"User-Agent": "wayrun-cc/1.0"})
        with urllib.request.urlopen(req, timeout=8) as resp:
            data = json.load(resp)
    except (OSError, ValueError):
        return None
    rates = data.get("rates")
    if data.get("result") != "success" or not isinstance(rates, dict):
        return None
    return {code: float(v) for code, v in rates.items()}


def cached_rates() -> dict[str, float] | None:
    """The cache when it is within the TTL, else None."""
    if not CACHE_PATH.exists():
        return None
    try:
        data = json.loads(CACHE_PATH.read_text(encoding="utf-8"))
        if time.time() - data["fetched_at"] > TTL_SECONDS:
            return None
        return data["rates"]
    except (OSError, ValueError, KeyError):
        return None


def save_rates(rates: dict[str, float]) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    tmp = CACHE_PATH.with_suffix(".tmp")
    payload = {"fetched_at": time.time(), "rates": rates}
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)
    tmp.replace(CACHE_PATH)  # atomic, so a partial write cannot corrupt the file


def rates() -> tuple[dict[str, float] | None, str]:
    """Return ``(rate table, source)``.

    The source is ``"cache"`` for a fresh cache hit, ``"er-api"`` when just
    fetched, and ``""`` with ``(None, "")`` when neither is available.
    """
    fresh = cached_rates()
    if fresh is not None:
        return fresh, "cache"
    online = fetch_rates()
    if online is not None:
        save_rates(online)
        return online, "er-api"
    return None, ""


def fmt(value: float) -> str:
    """Amount display: thousands with two decimals at >=1, else significant."""
    if value >= 1:
        return f"{value:,.2f}"
    return f"{value:.8f}".rstrip("0").rstrip(".")


@plugin.search(
    id="cc",
    name="CC Converter",
    keyword="cc",
    icon=ICON,
    description="Currency converter: cc <amount> <from> <to>",
)
def search(text: str) -> list[Item]:
    args = text.split()
    if len(args) > 3:
        return [hint("Too many arguments", "Usage: cc <amount> <from> <to>")]

    if len(args) == 1:
        amount = args[0]
        if not _is_number(amount):
            return [hint(f"Invalid amount: '{amount}'", "e.g. cc 100 usd cny")]
        return [hint(f"cc {amount} <from> <to>", "Now type the source currency")]

    if len(args) == 2:
        amount, fr = args[0], args[1]
        if not _is_number(amount):
            return [hint(f"Invalid amount: '{amount}'", "e.g. cc 100 usd cny")]
        code = normalize(fr)
        if code is None:
            return [hint(f"Unsupported currency: '{fr}'", _currency_hint())]
        return [hint(f"cc {amount} {code} <to>", "Now type the target currency")]

    amount, fr, to = args
    if not _is_number(amount):
        return [hint(f"Invalid amount: '{amount}'", "e.g. cc 100 usd cny")]
    src = normalize(fr)
    dst = normalize(to)
    if src is None:
        return [hint(f"Unsupported currency: '{fr}'", _currency_hint())]
    if dst is None:
        return [hint(f"Unsupported currency: '{to}'", _currency_hint())]

    table, source = rates()
    if table is None:
        return [hint("Cannot fetch rates", "Check the network and retry")]
    if src not in table or dst not in table:
        return [hint(f"No rate for {src}/{dst}", "Missing from the rate table")]

    value = float(amount) * table[dst] / table[src]
    inverse = table[src] / table[dst]
    summary = (
        f"{amount} {src} = {fmt(value)} {dst}"
        f" · 1 {dst} ≈ {fmt(inverse)} {src} · {source}"
    )
    return [
        Item(
            title=f"{fmt(value)} {dst}",
            summary=summary,
            on_click=copy_text(f"{fmt(value)} {dst}"),
        ),
    ]


def _is_number(s: str) -> bool:
    try:
        float(s)
        return True
    except ValueError:
        return False


def _currency_hint() -> str:
    return (
        "Supports ISO codes and aliases (usd/dollar, cny/yuan/rmb, eur, jpy, gbp, ...)"
    )


@plugin.default_view
def top() -> list[Item]:
    """Usage shown when cc is opened with an empty query."""
    return [hint("cc <amount> <from> <to>", "e.g. cc 1 yun usd · cc 100 usd jpy")]


plugin.run()
