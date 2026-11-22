#!/usr/bin/env -S wayrun --lua-host

local icon = wayrun.icon("papirus:github")
local copy_icon = wayrun.icon("papirus:edit-copy")
local git_icon = wayrun.icon("papirus:git")

local BASE = "https://api.github.com"
local SEARCH_REPOS = "/search/repositories"
local SEARCH_USERS = "/search/users"
local USER_REPOS = "/user/repos"
local STARRED = "/user/starred"

-- Own and starred repos come from listing endpoints: a token lists the user's
-- repositories directly, and search has no "starred by me" qualifier
-- (`is:starred` is ignored). Keywords filter the newest 400 entries locally.
local LIST_PER_PAGE = 100
local MAX_LIST_PAGES = 4
local MAX_ROWS = 8

-- Search repeats on backspace and benefits from a long cache; a listing is
-- sorted by push time, so a new push should surface within half a minute.
local SEARCH_TTL = 300
local LIST_TTL = 30

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

local function fetch(path, params, token, ttl)
  local ok, res = pcall(wayrun.http.get, BASE .. path, params, {
    headers = headers(token),
    ttl = ttl or SEARCH_TTL,
    timeout_ms = 3000
  })
  if not ok then
    wayrun.log("github " .. path .. ": " .. tostring(res))
    error(res, 0)
  end
  return res
end

-- Search answers { items = {...} }; the listing endpoints answer a bare array.
local function items_of(data)
  if type(data) ~= "table" or data.message then
    return {}
  end
  return data.items or data
end

local function items_from(res)
  if not res or not res.body then
    return {}
  end
  local ok, data = pcall(wayrun.json.decode, res.body)
  if not ok then
    wayrun.log("github: malformed reply: " .. tostring(data))
    return {}
  end
  return items_of(data)
end

local function query(path, params, token, ttl)
  local res = fetch(path, params, token, ttl)
  -- Search answers without a token too; a revoked one should not blank it.
  if res and res.status == 401 and token ~= "" and path:find("/search/", 1, true) then
    res = fetch(path, params, "", ttl)
  end
  if not res then
    return {}
  end
  if res.status ~= 200 then
    wayrun.log("github " .. path .. " -> HTTP " .. tostring(res.status))
    return {}, res.status
  end
  return items_from(res)
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
  local items = items_from(wayrun.http.cached(BASE .. path, params, {
    headers = headers(token)
  }))
  if #items > 0 then
    emit(rows(items, row))
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

local function failure_summary(status)
  if status == 401 then
    return t("The token was rejected; update GITHUB_TOKEN or the token file",
      "Token 被拒绝，请更新 GITHUB_TOKEN 或 token 文件")
  end
  if status == 403 then
    return t("GitHub denied the request; check the token or wait for the rate limit",
      "GitHub 拒绝访问，请检查 token 或等待限流解除")
  end
  if status == 422 then
    return t("GitHub rejected the search query", "GitHub 拒绝了该搜索查询")
  end
  return t("GitHub returned HTTP " .. tostring(status),
    "GitHub 返回 HTTP " .. tostring(status))
end

local function failure_hint(status)
  return {
    hint_row(t("GitHub request failed", "GitHub 请求失败"), failure_summary(status))
  }
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

-- Without `affiliation`, `/user/repos` also returns collaborator and
-- organisation-member repositories; owned-only matches what `user:@me` gave.
-- `pushed` is the last commit push; `updated` also moves on metadata edits.
local function user_repo_params(page)
  return {
    per_page = LIST_PER_PAGE,
    page = page,
    sort = "pushed",
    direction = "desc",
    affiliation = "owner"
  }
end

-- `created` puts the newest star first; `updated` the most recently pushed repo.
local function starred_params(page)
  return {
    per_page = LIST_PER_PAGE,
    page = page,
    sort = "created",
    direction = "desc"
  }
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

-- Stops at MAX_ROWS matches or the first short page; a bare listing then
-- costs one request, and a rare keyword scans deeper only because it must.
local function collect_matches(page_items, needles)
  local out = {}
  local seen = {}
  for page = 1, MAX_LIST_PAGES do
    local items, status = page_items(page)
    if status then
      return out, status
    end
    for _, repo in ipairs(items) do
      local name = text_of(repo.full_name)
      if not seen[name] and repo_matches(repo, needles) then
        seen[name] = true
        out[#out + 1] = repo
        if #out >= MAX_ROWS then
          return out
        end
      end
    end
    if #items < LIST_PER_PAGE then
      break
    end
  end
  return out
end

local function list_repo_rows(path, params_of, text, token, emit)
  local needles = needles_of(text)
  if emit then
    local cached = collect_matches(function(page)
      return items_from(wayrun.http.cached(BASE .. path, params_of(page), {
        headers = headers(token)
      }))
    end, needles)
    if #cached > 0 then
      emit(rows(cached, repo_row))
    end
  end
  local fresh, status = collect_matches(function(page)
    return query(path, params_of(page), token, LIST_TTL)
  end, needles)
  if #fresh == 0 and status then
    return failure_hint(status)
  end
  return rows(fresh, repo_row)
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
      t("m / mine <keywords> · bare m lists most recently pushed",
        "m / mine <关键词> · 仅输入 m 按最近提交列出")
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
        local items, status = query(SEARCH_USERS, params, token)
        if #items == 0 and status then
          return failure_hint(status)
        end
        return rows(items, user_row)
      end

      if MINE[mode] then
        if token == "" then
          return token_hint()
        end
        return list_repo_rows(USER_REPOS, user_repo_params, rest, token, emit)
      end

      if STAR[mode] then
        if token == "" then
          return token_hint()
        end
        return list_repo_rows(STARRED, starred_params, rest, token, emit)
      end

      if REPO[mode] then
        if rest == "" then
          return repo_hint()
        end
        text = rest
      end

      local params = { q = text, per_page = 8 }
      emit_cached(SEARCH_REPOS, params, token, emit, repo_row)
      local items, status = query(SEARCH_REPOS, params, token)
      if #items == 0 and status then
        return failure_hint(status)
      end
      return rows(items, repo_row)
    end
  }
}
