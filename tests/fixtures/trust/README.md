Fixtures for tests/trust_spec.lua. The suite copies them into temporary
directories; `__PORT__` is replaced by a local listener's port.

- `beacon/`: files whose `$schema` points at the listener (modeline, https
  modeline, top-level `$schema:`, IntelliJ comment, JSON `$schema`). No
  connection may reach it.
- `compose.yaml`: must be validated against the vendored compose schema.
- `nested.luarc.json`: a hostile-looking lua_ls config in a subdirectory of a
  trusted repo. lua_ls must not start there until that directory is trusted.
