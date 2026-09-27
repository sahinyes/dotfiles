-- YAML. Offline by design: only the schemas vendored in nvim/schemas are
-- used, and every download (SchemaStore, `$schema:` URLs, modelines) is sent
-- to a dead local proxy, so a hostile file cannot make it call home.
local dead_proxy = 'http://127.0.0.1:9' -- port 9 (discard): nothing listens

local function schema(name) return vim.uri_from_fname(vim.fn.stdpath('config') .. '/schemas/' .. name) end

return {
  -- Bare name from PATH: nvim-lspconfig would prefer <root>/node_modules/.bin.
  cmd = { 'yaml-language-server', '--stdio' },
  filetypes = { 'yaml' }, -- upstream also lists yaml.* variants unknown to Neovim
  -- request-light (the server's HTTP client) reads these until the settings
  -- below arrive, which closes the window right after startup.
  cmd_env = { HTTP_PROXY = dead_proxy, HTTPS_PROXY = dead_proxy, http_proxy = dead_proxy, https_proxy = dead_proxy },
  settings = {
    redhat = { telemetry = { enabled = false } },
    http = { proxy = dead_proxy, proxyStrictSSL = true },
    yaml = {
      schemaStore = { enable = false },
      kubernetesCRDStore = { enable = false },
      -- Globs match anywhere below the workspace (the server adds **/).
      schemas = {
        [schema('compose-spec.json')] = {
          'compose.{yml,yaml}',
          'compose.*.{yml,yaml}',
          'docker-compose.{yml,yaml}',
          'docker-compose.*.{yml,yaml}',
        },
        [schema('github-workflow.json')] = { '.github/workflows/*.{yml,yaml}' },
        [schema('nuclei.json')] = { 'nuclei-templates/**/*.{yml,yaml}', '*.nuclei.{yml,yaml}' },
      },
    },
  },
}
