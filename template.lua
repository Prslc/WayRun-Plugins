#!/usr/bin/env -S wayrun --lua-host
-- WayRun Lua plugin skeleton.
--
-- Copy this file, edit the table below, keep the shebang and the exec bit
-- (chmod +x), and register it in ~/.config/wayrun/plugins.toml:
--
--     [[plugins]]
--     id = "my-plugin"
--     keyword = "mp"    # or "" to join the default chain (listed fallback)
--     command = "/absolute/path/to/my-plugin.lua"
--     resident = true    # keep one host process warm between calls
--
-- Debug with print() or wayrun.log(): both write to the journal, never stdout.
-- Split a larger plugin with wayrun.import("lib/util") (same sandbox, cached).
--
-- The full surface (wayrun.sqlite, wayrun.http, wayrun.fs, ...) is documented
-- at https://github.com/Prslc/WayRun/blob/main/docs/en/lua.md.

local zh = wayrun.locale():match("^zh") ~= nil
local function t(en, cn)
  return zh and cn or en
end

return {
  {
    id = "my-plugin",                    -- must match the plugins.toml id
    name = t("My Plugin", "我的插件"),
    -- icon = wayrun.script_dir() .. "/icon.svg", -- an icon file you ship beside the script
    description = t("Does something useful", "做点有用的事"),
    api = 1,                             -- the plugin contract it was written against
    -- env = { "MY_TOKEN" },             -- the exact env names it may read
    -- read = { "~/Documents" },         -- the areas it may look inside

    search = function(text)
      if text == "" then
        return {}
      end
      return {
        {
          title = t("You searched: ", "你搜索了：") .. text,
          on_click = { type = "copy", text = text },
        },
      }
    end,

    -- Optional: the empty-query view, shown when opened with the keyword and
    -- nothing typed.
    -- top = function() return {} end,
  },
}
