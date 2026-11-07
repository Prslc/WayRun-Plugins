#!/usr/bin/env -S wayrun --lua-host
-- Currency converter over the open.er-api.com daily rates.
-- The rate cache lives in this process: it survives between calls only while
-- the host is resident, and a restart refetches.

local ICON = wayrun.script_dir() .. "/assets/currency_icon.svg"
local RATES_URL = "https://open.er-api.com/v6/latest/USD"
local TTL_SECONDS = 12 * 3600

local zh = wayrun.locale():match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

local ALIASES = {
  usd = "USD", dollar = "USD", us = "USD",
  cny = "CNY", yuan = "CNY", yun = "CNY", rmb = "CNY", renminbi = "CNY",
  eur = "EUR", euro = "EUR",
  jpy = "JPY", yen = "JPY",
  gbp = "GBP", pound = "GBP",
  hkd = "HKD",
  twd = "TWD", nt = "TWD",
  krw = "KRW", won = "KRW",
  aud = "AUD", cad = "CAD", chf = "CHF", sgd = "SGD", nzd = "NZD",
  thb = "THB", inr = "INR", myr = "MYR", idr = "IDR", vnd = "VND",
  php = "PHP", sek = "SEK", nok = "NOK", brl = "BRL", mxn = "MXN",
  zar = "ZAR", try = "TRY", ils = "ILS",
}

local function normalize(code)
  local c = code:gsub("^%s+", ""):gsub("%s+$", "")
  if ALIASES[c:lower()] then
    return ALIASES[c:lower()]
  end
  if #c == 3 and c:match("^%a+$") then
    return c:upper()
  end
  return nil
end

local cache = nil

local function fetch_rates()
  local ok, res = pcall(wayrun.http.get, RATES_URL, nil, 8000)
  if not ok then
    return nil
  end
  local ok_decode, data = pcall(wayrun.json.decode, res.body)
  if not ok_decode or type(data) ~= "table" or data.result ~= "success" or type(data.rates) ~= "table" then
    return nil
  end
  return data.rates
end

local function rates()
  if cache and wayrun.time() - cache.at < TTL_SECONDS then
    return cache.rates, "cache"
  end
  local table_ = fetch_rates()
  if table_ then
    cache = { at = wayrun.time(), rates = table_ }
    return table_, "er-api"
  end
  if cache then
    return cache.rates, "stale cache"
  end
  return nil, ""
end

local function group(int)
  local reversed = int:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (reversed:gsub("^,", ""))
end

local function fmt(value)
  if value >= 1 then
    local int, frac = string.format("%.2f", value):match("^(%d+)(%.%d+)$")
    return group(int) .. frac
  end
  return (string.format("%.8f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function hint(title, detail)
  return { title = title, summary = detail }
end

local function hint_row(title, detail)
  return { hint(title, detail) }
end

local function is_number(text)
  return tonumber(text) ~= nil
end

local function currency_hint()
  return t(
    "Supports ISO codes and aliases (usd/dollar, cny/yuan/rmb, eur, jpy, gbp, ...)",
    "支持 ISO 代码与别名（usd/dollar、cny/yuan/rmb、eur、jpy、gbp 等）"
  )
end

local function search(text)
  local args = {}
  for word in text:gmatch("%S+") do
    args[#args + 1] = word
  end
  if #args > 3 then
    return hint_row(
      t("Too many arguments", "参数过多"),
      t("Usage: <amount> <from> <to>", "用法：<金额> <源货币> <目标货币>")
    )
  end
  if #args == 0 then
    return hint_row(
      t("<amount> <from> <to>", "<金额> <源货币> <目标货币>"),
      t("e.g. 1 cny usd · 100 usd jpy", "例如 1 cny usd · 100 usd jpy")
    )
  end

  if #args == 1 then
    if not is_number(args[1]) then
      return hint_row(
        t("Invalid amount: '" .. args[1] .. "'", "金额无效：'" .. args[1] .. "'"),
        t("e.g. 100 usd cny", "例如 100 usd cny")
      )
    end
    return hint_row(
      t("<amount> " .. args[1] .. " <from> <to>", "<金额> " .. args[1] .. " <源货币> <目标货币>"),
      t("Now type the source currency", "接下来输入源货币")
    )
  end

  if #args == 2 then
    if not is_number(args[1]) then
      return hint_row(
        t("Invalid amount: '" .. args[1] .. "'", "金额无效：'" .. args[1] .. "'"),
        t("e.g. 100 usd cny", "例如 100 usd cny")
      )
    end
    local code = normalize(args[2])
    if not code then
      return hint_row(
        t("Unsupported currency: '" .. args[2] .. "'", "不支持的货币：'" .. args[2] .. "'"),
        currency_hint()
      )
    end
    return hint_row(
      t("<amount> " .. args[1] .. " " .. code .. " <to>", "<金额> " .. args[1] .. " " .. code .. " <目标货币>"),
      t("Now type the target currency", "接下来输入目标货币")
    )
  end

  local amount, from, to = args[1], args[2], args[3]
  if not is_number(amount) then
    return hint_row(
      t("Invalid amount: '" .. amount .. "'", "金额无效：'" .. amount .. "'"),
      t("e.g. 100 usd cny", "例如 100 usd cny")
    )
  end
  local src = normalize(from)
  local dst = normalize(to)
  if not src then
    return hint_row(
      t("Unsupported currency: '" .. from .. "'", "不支持的货币：'" .. from .. "'"),
      currency_hint()
    )
  end
  if not dst then
    return hint_row(
      t("Unsupported currency: '" .. to .. "'", "不支持的货币：'" .. to .. "'"),
      currency_hint()
    )
  end

  local table_, source = rates()
  if not table_ then
    return hint_row(
      t("Cannot fetch rates", "无法获取汇率"),
      t("Check the network and retry", "检查网络后重试")
    )
  end
  if not table_[src] or not table_[dst] then
    return hint_row(
      t("No rate for " .. src .. "/" .. dst, "缺少 " .. src .. "/" .. dst .. " 的汇率"),
      t("Missing from the rate table", "汇率表中没有这一项")
    )
  end

  local value = tonumber(amount) * table_[dst] / table_[src]
  local inverse = table_[src] / table_[dst]
  local source_label = source
  if source == "cache" then
    source_label = t("cache", "缓存")
  elseif source == "stale cache" then
    source_label = t("stale cache", "过期缓存")
  end
  local summary = amount
    .. " "
    .. src
    .. " = "
    .. fmt(value)
    .. " "
    .. dst
    .. " · 1 "
    .. dst
    .. " ≈ "
    .. fmt(inverse)
    .. " "
    .. src
    .. " · "
    .. source_label
  return {
    {
      title = fmt(value) .. " " .. dst,
      summary = summary,
      on_click = { type = "copy", text = fmt(value) .. " " .. dst },
    },
  }
end

return {
  {
    id = "currency",
    name = t("Currency Converter", "汇率换算"),
    icon = ICON,
    description = t("Convert between currencies", "汇率换算：金额 源货币 目标货币"),
    api = 1,
    search = search,
    top = function()
      return hint_row(
        t("<amount> <from> <to>", "<金额> <源货币> <目标货币>"),
        t("e.g. 1 cny usd · 100 usd jpy", "例如 1 cny usd · 100 usd jpy")
      )
    end,
  },
}
