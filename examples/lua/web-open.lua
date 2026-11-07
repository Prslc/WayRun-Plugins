#!/usr/bin/env -S wayrun --lua-host
-- Opens a typed URL or bare domain in the default browser. Anything that does
-- not look like a web address yields no rows, so the default chain stays out
-- of the other providers' way.

local assets = wayrun.script_dir() .. "/assets/"
local browser_icon = wayrun.icon("web-browser") or wayrun.icon("applications-internet")
local copy_icon = assets .. "copy_icon.svg"

local CATALOGS = {
  en = {
    name = "Open Web",
    description = "Open a URL or domain in the browser",
    open = "Open in browser",
    copy = "Copy URL",
  },
  zh_cn = {
    name = "网页直达",
    description = "输入网址或域名，用浏览器打开",
    open = "在浏览器中打开",
    copy = "复制网址",
  },
}
local fallback = CATALOGS.en
local strings = CATALOGS[wayrun.locale()] or fallback
local function t(key)
  return strings[key] or fallback[key]
end

-- A whitelist keeps file names such as `main.rs` or `notes.md` from being
-- taken for domains, while still covering the usual ones.
local TLDS = {
  com = true, org = true, net = true, edu = true, gov = true, mil = true, int = true,
  io = true, dev = true, app = true, ai = true, me = true, tv = true, xyz = true,
  info = true, biz = true, co = true, gg = true, to = true,
  cn = true, uk = true, de = true, fr = true, jp = true, ru = true, us = true,
  ca = true, au = true, br = true, ["in"] = true, it = true, nl = true, se = true,
  no = true, es = true, pl = true, ch = true, at = true, be = true, dk = true,
  fi = true, cz = true, gr = true, hu = true, ie = true, il = true, mx = true,
  nz = true, pt = true, ro = true, sk = true, tr = true, ua = true, za = true,
  kr = true, tw = true, hk = true, sg = true,
}

local function direct_url(text)
  if text:lower():match("^https?://%S+$") then
    return text
  end

  local host, path = text:match("^([%w%-][%w%.%-]*%.[%a][%a%-]+)(/%S*)$")
  if not host then
    host = text:match("^([%w%-][%w%.%-]*%.[%a][%a%-]+)$")
  end
  if not host then
    return nil
  end

  local tld = host:match("%.([%a][%a%-]+)$"):lower()
  if host:lower():sub(1, 4) ~= "www." and not TLDS[tld] then
    return nil
  end
  return "https://" .. host .. (path or "")
end

local function row(url, title)
  return {
    title = title,
    summary = url,
    icon = browser_icon,
    on_click = { type = "open", uri = url },
    actions = {
      {
        title = t("copy"),
        id = "copy_url",
        action = { type = "copy", text = url },
        icon = copy_icon,
      },
    },
  }
end

local function search_rows(text)
  text = text:gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then
    return {}
  end
  local url = direct_url(text)
  if not url then
    return {}
  end
  return { row(url, t("open")) }
end

return {
  {
    id = "web-open",
    name = t("name"),
    icon = browser_icon,
    description = t("description"),
    api = 1,
    search = search_rows,
  },
}
