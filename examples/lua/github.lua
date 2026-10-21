#!/usr/bin/env -S wayrun --lua-host

local icon = wayrun.icon("papirus:github")
local copy_icon = wayrun.icon("papirus:edit-copy")
local git_icon = wayrun.icon("papirus:git")

local zh = wayrun.locale():match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

local function avatar(owner)
  local url = owner and owner.avatar_url
  if not url or url == "" then
    return nil
  end
  local sep = url:find("?", 1, true) and "&" or "?"
  return url .. sep .. "s=64"
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

local function fetch(path, text, token)
  return wayrun.http.get("https://api.github.com" .. path, {
    q = text,
    per_page = 8
  }, {
    headers = headers(token),
    ttl = 300,
    timeout_ms = 3000
  })
end

local function query(path, text, token)
  local res = fetch(path, text, token)
  if res and res.status == 401 and token ~= "" then
    res = fetch(path, text, "")
  end
  if not res or res.status ~= 200 or not res.body then
    return {}
  end
  local ok, data = pcall(wayrun.json.decode, res.body)
  if not ok or not data or not data.items then
    return {}
  end
  return data.items
end

local function rows(items, row)
  local out = {}
  for _, item in ipairs(items) do
    table.insert(out, row(item))
  end
  return out
end

local function emit_cached(path, text, token, emit, row)
  if not emit then
    return
  end
  local cached = wayrun.http.cached("https://api.github.com" .. path, {
    q = text,
    per_page = 8
  }, {
    headers = headers(token)
  })
  if not cached or not cached.body then
    return
  end
  local ok, data = pcall(wayrun.json.decode, cached.body)
  if ok and data and data.items then
    emit(rows(data.items, row))
  end
end

local function repo_row(repo)
  local repo_avatar = avatar(repo.owner)
  return {
    title = repo.full_name,
    summary = (repo.description and repo.description ~= "") and repo.description or repo.html_url,
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

return {
  {
    id = "github",
    name = "GitHub",
    icon = icon,
    description = t("Search GitHub repositories and users", "搜索 GitHub 仓库与用户"),
    api = 1,
    env = { "GITHUB_TOKEN" },
    search = function(text, emit)
      if not text or text == "" then
        return {}
      end

      local token = wayrun.env("GITHUB_TOKEN") or ""
      local mode, rest = text:match("^(%S+)%s+(.+)$")
      if mode and mode:lower() == "user" then
        emit_cached("/search/users", rest, token, emit, user_row)
        return rows(query("/search/users", rest, token), user_row)
      end
      if text:lower() == "user" then
        return {
          {
            title = t("Search GitHub users", "搜索 GitHub 用户"),
            summary = t("Type a login, e.g. user torvalds", "输入用户名，例如 user torvalds"),
            icon = icon
          }
        }
      end
      emit_cached("/search/repositories", text, token, emit, repo_row)
      return rows(query("/search/repositories", text, token), repo_row)
    end
  }
}
