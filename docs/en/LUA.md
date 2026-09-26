# Lua plugins

A plugin can also be one Lua script — no framework, no Python install. The
WayRun binary hosts it itself (`wayrun --lua-host`), answering the same
JSON-RPC surface a Python host does, so it starts in milliseconds — and
everything the launcher provides is reachable through one `wayrun` table.

## Writing a script

A script returns a list of plugin tables; each table is one plugin:

```lua
#!/usr/bin/env -S wayrun --lua-host
return {
  {
    id = "my-plugin",                    -- must match the plugins.toml id
    name = "My Plugin",
    icon = wayrun.icon("builtin:globe"), -- an absolute path, or nil
    description = "Short description",
    search = function(text)              -- rows for a routed query, in order
      return {
        { title = "You searched: " .. text,
          on_click = { type = "copy", text = text } },
      }
    end,
    top = function() end,                -- optional: the empty-query view
    forget = function(action) end,       -- optional: claim a row for removal
  },
}
```

Rows are the result items of the wire protocol: `title`, `summary`, `on_click`
(an action), `icon`, `ephemeral`, `actions`, `badge`. No builder is needed — a
table in the wire shape is enough, for example
`on_click = { type = "open", uri = "https://example.com" }`.

## The `wayrun` table

| Call | Does |
| --- | --- |
| `wayrun.home()` | `$HOME`, or nil |
| `wayrun.cache_dir()` | the launcher's cache directory, or nil |
| `wayrun.icon(spec)` | resolves `builtin:…`, a theme name or `papirus:…` to an absolute path; nil on a miss |
| `wayrun.urlencode(text)` | percent-encodes for use in a URL |
| `wayrun.t(key, args)` | a UI string from the launcher's own tables, with `%{name}` filled from `args` |
| `wayrun.log(message)` | writes to the launcher's journal under the script's name |
| `wayrun.web_search_engine()` | the configured search engine, e.g. `"google"` |
| `wayrun.time()` | Unix seconds, for signatures and cache TTLs |
| `wayrun.env(name)` | the launcher process's variable `name`, or nil |
| `wayrun.which(name)` | an executable's path on the launcher's `$PATH`, or nil; the same PATH a `run` row's command will see |
| `wayrun.script_dir()` | the script's own directory, for an icon it ships |
| `wayrun.plugin_dir(id)` | the directory a plugin may read from, `~/.config/wayrun/plugins/<id>` |
| `wayrun.fs.read(name)` | a file under those directories; a relative name, nil when absent, an error when the name escapes |
| `wayrun.toml.decode(text)` | TOML in, a table out |
| `wayrun.json.decode(text)` / `wayrun.json.encode(value)` | JSON in and out |
| `wayrun.fs.list(dir)` | entry names under `dir`, or nil |
| `wayrun.fs.stat(path)` | `{ mtime_ns, size }`, or nil |
| `wayrun.http.get(url, params?, timeout_ms?)` | blocking GET, answering `{status, body}`; a transport error raises; `params` adds query values and takes a reserved `headers` table for request headers |
| `wayrun.sqlite.snapshot(path)` | an immutable copy of a SQLite file, opened and returned as a handle |
| `wayrun.sqlite.query(handle, sql, params?)` | rows as tables; a NULL column reads as absent |
| `wayrun.kv.get(key)` | a stored string, or nil when absent or expired |
| `wayrun.kv.set(key, value, ttl_secs?)` | stores a string under `key`; with a ttl it expires; the store is a sqlite database in the plugin's own directory |
| `wayrun.kv.delete(key)` | drops a key |
| `wayrun.fuzzy.match(query, candidates)` | `{index, kind}` hits, best first, over an array of strings; the kinds are the launcher's own (exact, prefix, word, substring, loose) |

## The sandbox

`os`, `io`, `package`, `load` and `print` are not reachable: a script cannot
run programs, and the only write is `kv`, whose keys are not paths and whose
database lives in the plugin's own directory. Reading is wider: `fs.read` is
the scoped one (relative names only, confined to
`~/.config/wayrun/plugins/<id>/`), while `fs.list` and `fs.stat` take any path
for names and metadata, `sqlite.snapshot` copies any SQLite file for querying
(`firefox.lua` reads `places.sqlite` this way), `wayrun.env` reads the
launcher's environment, and `http.get` reaches the network. The sandbox bounds
what a script can do, not what it can read. A call that raises yields no rows
and reports to the journal, so `wayrun.log` and a `pcall` around risky work are
the debugging tools.

## Limits

- A Lua plugin needs a non-empty keyword: it answers its own routed queries.
  The default chain (keyword `""`) is reserved for the built-ins.
- Rows keep the order the script returns; there is no relevance channel.
- Icons must be absolute paths; `wayrun.icon` is how to get one.

## Registering

Copy `template.lua`, keep the shebang and the exec bit (`chmod +x`), and
register it like any host — a single executable token:

```toml
[[plugins]]
id = "my-plugin"          # must match the returned plugin id
keyword = "mp"
command = "/absolute/path/to/my-plugin.lua"
resident = true           # keep the host warm between calls
```

The first line of the script must be
`#!/usr/bin/env -S wayrun --lua-host`. `example/lua/firefox.lua` and
`example/lua/web.lua` are complete worked examples, reading `places.sqlite`
and the web respectively.
