#!/usr/bin/env -S wayrun --lua-host
-- WayRun Lua plugin skeleton.
--
-- Copy this file, edit the table below, keep the shebang and the exec bit
-- (chmod +x), and register it in ~/.config/wayrun/plugins.toml:
--
--     [[plugins]]
--     id = "my-plugin"
--     keyword = "mp"
--     command = "/absolute/path/to/my-plugin.lua"
--     resident = true    # keep one host process warm between calls
--
-- The full surface (wayrun.sqlite, wayrun.http, wayrun.fs, ...) is
-- documented in this workspace's docs/en/LUA.md.

return {
  {
    id = "my-plugin",                    -- must match the plugins.toml id
    name = "My Plugin",
    icon = wayrun.icon("builtin:globe"), -- an absolute path or `builtin:` glyph, or nil
    description = "Does something useful",
    -- env = { "MY_TOKEN" },             -- the exact env names it may read
    -- read = { "~/Documents" },         -- the areas it may look inside

    search = function(text)
      if text == "" then
        return {}
      end
      return {
        {
          title = "You searched: " .. text,
          on_click = { type = "copy", text = text },
        },
      }
    end,

    -- Optional: the empty-query view, shown when opened with the keyword and
    -- nothing typed.
    -- top = function() return {} end,
  },
}
