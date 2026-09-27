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
    env = { "MY_TOKEN" },                -- the env names it may read
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

The plugin table doubles as the plugin's manifest: `env` lists the exact
environment variable names it may read, no patterns. An undeclared name raises;
a declared-but-unset one is nil. Reads work inside `search`/`top`/`forget` and
not while the script loads — for the paths a script would otherwise take from
the environment, use `wayrun.home()` and `wayrun.cache_dir()`.

`read` lists the areas a plugin may read — absolute paths or `~/…`, exact, no
patterns. Symlinks are resolved on every read, so a link inside an area cannot
lead out of it; `fs.list`, `fs.stat` and `sqlite.snapshot` raise for anything
outside those areas, while the plugin's own directory and the script's
directory are always inside.

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
| `wayrun.env(name)` | a variable the plugin declares in `env`, or nil when unset; an undeclared name raises |
| `wayrun.which(name)` | an executable's path on the launcher's `$PATH`, or nil; the same PATH a `run` row's command will see |
| `wayrun.script_dir()` | the script's own directory, for an icon it ships |
| `wayrun.plugin_dir(id)` | the directory a plugin may read from, `~/.config/wayrun/plugins/<id>` |
| `wayrun.fs.read(name)` | a file under those directories; a relative name, nil when absent, an error when the name escapes |
| `wayrun.toml.decode(text)` | TOML in, a table out |
| `wayrun.json.decode(text)` / `wayrun.json.encode(value)` | JSON in and out |
| `wayrun.fs.list(dir)` | entry names under `dir` inside a declared area, or nil |
| `wayrun.fs.stat(path)` | `{ mtime_ns, size }` for a path inside a declared area, or nil |
| `wayrun.http.get(url, params?, options?)` | blocking GET answering `{status, headers, body}`; a transport error raises; `params` adds query values and takes a reserved `headers` table; `options` is a table with `timeout_ms`, `headers` and `ttl`, or a bare timeout in ms |
| `wayrun.http.post(url, params?, options?)` | the same, sending one body: `json = value`, `form = {…}` or `body = "…"`; never cached |
| `wayrun.crypto.sha256(text)` / `wayrun.crypto.md5(text)` | lowercase hex digest |
| `wayrun.crypto.hmac_sha256(key, text)` | lowercase hex HMAC |
| `wayrun.crypto.base64_encode(data)` / `wayrun.crypto.base64_decode(text)` | base64 both ways over raw bytes; decode answers nil on garbage |
| `wayrun.sqlite.snapshot(path)` | an immutable copy of a SQLite file inside a declared area, opened and returned as a handle; one file answers one handle, following its newest copy |
| `wayrun.sqlite.query(handle, sql, params?)` | rows as tables; a NULL column reads as absent; a handle's source file must lie inside the calling plugin's areas |
| `wayrun.kv.get(key)` | a stored string, or nil when absent or expired |
| `wayrun.kv.set(key, value, ttl_secs?)` | stores a string under `key`; with a ttl it expires; the store is a sqlite database in the plugin's own directory |
| `wayrun.kv.delete(key)` | drops a key |
| `wayrun.kv.keys(prefix?)` / `wayrun.kv.pairs(prefix?)` | the unexpired keys, or `{key, value}` records, under a prefix, ordered by key |
| `wayrun.fuzzy.match(query, candidates)` | `{index, kind}` hits, best first, over an array of strings; the kinds are the launcher's own (exact, prefix, word, substring, loose) |

`http.get` with a `ttl` answers a repeated call from the plugin's own store
instead of the network — a 2xx text reply only, which is what makes a
per-keystroke query affordable. Replies carry the body as raw bytes and
lowercase response header names, and a timeout (two seconds by default) is
capped inside the host call's own ceiling, so a slow endpoint raises an error
for `pcall` rather than dying as a killed host.

## The sandbox

`os`, `io`, `package`, `load` and `print` are not reachable: a script cannot
run programs, and the only write is `kv`, whose keys are not paths and whose
database lives in the plugin's own directory. Reading is wider: `fs.read` is
the scoped one (relative names only, confined to
`~/.config/wayrun/plugins/<id>/`), while `fs.list`, `fs.stat` and
`sqlite.snapshot` reach only the areas a plugin declares for itself
(`firefox.lua` declares `~/.mozilla/firefox` for `places.sqlite`),
`wayrun.env` reads only the names the calling plugin declares, and `http`
reaches the network. The sandbox bounds what a script can do; what it can read
is what the plugin's `env` and `read` declare. A call that raises yields no rows
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
