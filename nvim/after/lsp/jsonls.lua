-- JSON. Offline like yamlls: schemas are read from file:// only; an http(s)
-- `$schema` is handed back to Neovim (which does not fetch it), and the
-- server's own HTTP client points at a dead local proxy.
local dead_proxy = 'http://127.0.0.1:9' -- port 9 (discard): nothing listens

return {
  -- Bare name from PATH: nvim-lspconfig would prefer <root>/node_modules/.bin.
  cmd = { 'vscode-json-language-server', '--stdio' },
  cmd_env = { HTTP_PROXY = dead_proxy, HTTPS_PROXY = dead_proxy, http_proxy = dead_proxy, https_proxy = dead_proxy },
  init_options = { handledSchemaProtocols = { 'file' } },
  settings = {
    http = { proxy = dead_proxy, proxyStrictSSL = true },
    -- The server turns validation off unless the client says otherwise.
    json = { validate = { enable = true } },
  },
}
