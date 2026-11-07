#!/usr/bin/env -S wayrun --lua-host

local icon = wayrun.icon("papirus:github")
local copy_icon = wayrun.icon("papirus:edit-copy")
local git_icon = wayrun.icon("papirus:git")

local SEARCH_REPOS = "/search/repositories"
local SEARCH_USERS = "/search/users"
local STARRED = "/user/starred"

-- GitHub search has no "starred by me" qualifier (`is:starred` is ignored), so
-- starred repos are listed and filtered here. Four pages cover 400 stars.
local STARRED_PER_PAGE = 100
local MAX_STARRED_PAGES = 4
local MAX_ROWS = 8

local USER = { user = true, u = true }
local MINE = { mine = true, my = true, m = true, ["我的"] = true }
local STAR = { star = true, starred = true, s = true, ["星标"] = true }
local REPO = { repo = true, r = true }

local zh = wayrun.locale():match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

-- The JSON decoder keeps null as a userdata sentinel, so absent fields are
-- checked by type rather than by truthiness.
local function text_of(value)
  return type(value) == "string" and value or ""
end

local function avatar(owner)
  local url = text_of(owner and owner.avatar_url)
  if url == "" then
    return nil
  end
  local sep = url:find("?", 1, true) and "&" or "?"
  return url .. sep .. "s=64"
end

-- The launcher runs from systemd, so a token exported in the user's shell does
-- not reach it. The plugin's own `token` file is the fallback for that.
local function github_token()
  local token = wayrun.env("GITHUB_TOKEN") or ""
  if token == "" then
    token = wayrun.fs.read("token") or ""
  end
  return (token:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function headers(token)
  local out = {
    ["Accept"] = "application/vnd.github+json",
    ["User-Agent"] = "WayRun-Plugin"
  }

  if token and token ~= "" then
    out["Authorization"] = "Bearer " .. token
  end

  return out
end

local function fetch(path, params, token)
  return wayrun.http.get("https://api.github.com" .. path, params, {
    headers = headers(token),
    ttl = 300,
    timeout_ms = 3000
  })
end

-- Search answers { items = {...} }; the listing endpoints answer a bare array.
local function items_of(data)
  if type(data) ~= "table" or data.message then
    return {}
  end
  return data.items or data
end

local function query(path, params, token)
  local res = fetch(path, params, token)
  if res and res.status == 401 and token ~= "" then
    res = fetch(path, params, "")
  end
  if not res or res.status ~= 200 or not res.body then
    return {}
  end
  local ok, data = pcall(wayrun.json.decode, res.body)
  if not ok then
    return {}
  end
  return items_of(data)
end

local function rows(items, row)
  local out = {}
  for _, item in ipairs(items) do
    table.insert(out, row(item))
  end
  return out
end

local function emit_cached(path, params, token, emit, row)
  if not emit then
    return
  end
  local cached = wayrun.http.cached("https://api.github.com" .. path, params, {
    headers = headers(token)
  })
  if not cached or not cached.body then
    return
  end
  local ok, data = pcall(wayrun.json.decode, cached.body)
  if ok then
    emit(rows(items_of(data), row))
  end
end

local function repo_row(repo)
  local repo_avatar = avatar(repo.owner)
  local description = text_of(repo.description)
  return {
    title = repo.full_name,
    summary = description ~= "" and description or repo.html_url,
    on_click = {
      type = "open",
      uri = repo.html_url
    },
    actions = {
      {
        title = t("Copy HTML URL", "复制 HTML 链接"),
        id = "copy_url",
        action = { type = "copy", text = repo.html_url },
        icon = copy_icon
      },
      {
        title = t("Copy Clone Command", "复制克隆命令"),
        id = "copy_clone",
        action = { type = "copy", text = "git clone " .. repo.clone_url },
        icon = git_icon
      }
    },
    icon = repo_avatar or icon,
    icon_shape = repo_avatar and "circle" or nil
  }
end

local function user_row(user)
  local user_avatar = avatar(user)
  return {
    title = user.login,
    summary = user.html_url,
    on_click = {
      type = "open",
      uri = user.html_url
    },
    actions = {
      {
        title = t("Copy profile URL", "复制主页链接"),
        id = "copy_url",
        action = { type = "copy", text = user.html_url },
        icon = copy_icon
      }
    },
    icon = user_avatar or icon,
    icon_shape = user_avatar and "circle" or nil
  }
end

local function hint_row(title, summary)
  return { title = title, summary = summary, icon = icon }
end

local function user_hint()
  return {
    hint_row(
      t("Search GitHub users", "搜索 GitHub 用户"),
      t("Type a login, e.g. u torvalds", "输入用户名，例如 u torvalds")
    )
  }
end

local function repo_hint()
  return {
    hint_row(
      t("Search GitHub repositories", "搜索 GitHub 仓库"),
      t("Type keywords, e.g. r launcher", "输入关键词，例如 r launcher")
    )
  }
end

local function token_hint()
  local dir = wayrun.plugin_dir("github")
  local where = dir and (dir .. "/token") or "token"
  return {
    hint_row(
      t("GitHub token required", "需要 GitHub Token"),
      t("Set GITHUB_TOKEN, or write the token to " .. where,
        "设置 GITHUB_TOKEN，或把 token 写入 " .. where)
    )
  }
end

local function mine_rows(text, token, emit)
  local params = { q = text == "" and "user:@me" or (text .. " user:@me"), per_page = 8 }
  if text == "" then
    params.sort = "updated"
    params.order = "desc"
  end
  emit_cached(SEARCH_REPOS, params, token, emit, repo_row)
  return rows(query(SEARCH_REPOS, params, token), repo_row)
end

local function starred_params(page)
  return {
    per_page = STARRED_PER_PAGE,
    page = page,
    sort = "created",
    direction = "desc"
  }
end

local function append_items(out, items)
  for _, item in ipairs(items) do
    out[#out + 1] = item
  end
end

local function starred_items(token)
  local out = {}
  for page = 1, MAX_STARRED_PAGES do
    local items = query(STARRED, starred_params(page), token)
    append_items(out, items)
    if #items < STARRED_PER_PAGE then
      break
    end
  end
  return out
end

local function cached_starred_items(token)
  local out = {}
  for page = 1, MAX_STARRED_PAGES do
    local cached = wayrun.http.cached("https://api.github.com" .. STARRED, starred_params(page), {
      headers = headers(token)
    })
    if cached and cached.body then
      local ok, data = pcall(wayrun.json.decode, cached.body)
      if ok then
        append_items(out, items_of(data))
      end
    end
  end
  return out
end

local function needles_of(text)
  local out = {}
  for word in text:lower():gmatch("%S+") do
    out[#out + 1] = word
  end
  return out
end

local function repo_matches(repo, needles)
  if #needles == 0 then
    return true
  end
  local parts = {
    text_of(repo.full_name),
    text_of(repo.description),
    text_of(repo.language),
    text_of(repo.owner and repo.owner.login)
  }
  if type(repo.topics) == "table" then
    for _, topic in ipairs(repo.topics) do
      parts[#parts + 1] = text_of(topic)
    end
  end
  local haystack = table.concat(parts, "\n"):lower()
  for _, needle in ipairs(needles) do
    if not haystack:find(needle, 1, true) then
      return false
    end
  end
  return true
end

local function star_rows(items, text)
  local needles = needles_of(text)
  local out = {}
  local seen = {}
  for _, repo in ipairs(items) do
    if #out >= MAX_ROWS then
      break
    end
    local name = text_of(repo.full_name)
    if not seen[name] and repo_matches(repo, needles) then
      seen[name] = true
      out[#out + 1] = repo
    end
  end
  return out
end

local function starred_rows(text, token, emit)
  if emit then
    local cached = star_rows(cached_starred_items(token), text)
    if #cached > 0 then
      emit(rows(cached, repo_row))
    end
  end
  return rows(star_rows(starred_items(token), text), repo_row)
end

local function top()
  local out = {
    hint_row(
      t("Search GitHub repositories", "搜索 GitHub 仓库"),
      t("r / repo <keywords>, or type keywords directly",
        "r / repo <关键词>，或直接输入关键词")
    ),
    hint_row(
      t("Search GitHub users", "搜索 GitHub 用户"),
      t("u / user <login>", "u / user <用户名>")
    )
  }
  local token = github_token()
  if token ~= "" then
    table.insert(out, hint_row(
      t("My repositories", "我的仓库"),
      t("m / mine <keywords> · bare m lists your latest",
        "m / mine <关键词> · 仅输入 m 列出最近更新")
    ))
    table.insert(out, hint_row(
      t("Starred repositories", "星标仓库"),
      t("s / star <keywords> · bare s lists your latest stars",
        "s / star <关键词> · 仅输入 s 列出最近星标")
    ))
  end
  return out
end

return {
  {
    id = "github",
    name = "GitHub",
    icon = icon,
    description = t("Search GitHub repositories, users, your own and starred repos",
      "搜索 GitHub 仓库、用户、自己的仓库与星标仓库"),
    api = 1,
    env = { "GITHUB_TOKEN" },
    top = top,
    search = function(text, emit)
      text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
      if text == "" then
        return {}
      end

      local token = github_token()
      local first, rest = text:match("^(%S+)%s+(.*)$")
      local mode = (first or text):lower()
      rest = rest and rest:gsub("^%s+", ""):gsub("%s+$", "") or ""

      if USER[mode] then
        if rest == "" then
          return user_hint()
        end
        local params = { q = rest, per_page = 8 }
        emit_cached(SEARCH_USERS, params, token, emit, user_row)
        return rows(query(SEARCH_USERS, params, token), user_row)
      end

      if MINE[mode] then
        if token == "" then
          return token_hint()
        end
        return mine_rows(rest, token, emit)
      end

      if STAR[mode] then
        if token == "" then
          return token_hint()
        end
        return starred_rows(rest, token, emit)
      end

      if REPO[mode] then
        if rest == "" then
          return repo_hint()
        end
        text = rest
      end

      local params = { q = text, per_page = 8 }
      emit_cached(SEARCH_REPOS, params, token, emit, repo_row)
      return rows(query(SEARCH_REPOS, params, token), repo_row)
    end
  }
}
