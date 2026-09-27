# Vendored JSON schemas

yamlls reads these files through `file://` URIs (see `nvim/after/lsp/yamlls.lua`).
They are vendored so the language server never downloads a schema. Its proxy
setting points at a dead local port, so a `$schema:` URL in a hostile file
cannot reach the network either.

Each file is an unmodified copy of the upstream file at the commit shown.

| File | Upstream (pinned commit) | License | sha256 | Fetched |
|---|---|---|---|---|
| `compose-spec.json` | https://raw.githubusercontent.com/compose-spec/compose-spec/914ec15d1fa498969c0df5c1d672306db3256089/schema/compose-spec.json | Apache-2.0 | `d61cc3df8c6e6a727043e84f3405c69ffd63d341f629db8480f1d2ee5405b10c` | 2026-09-27 |
| `github-workflow.json` | https://raw.githubusercontent.com/SchemaStore/schemastore/8b994c014937a9332f2fb53d993eb1a30705677c/src/schemas/json/github-workflow.json | Apache-2.0 | `d10c9f4656e1bd5bc6727e9b35080e017dc167154726fca93da33c7a6bd1c4f3` | 2026-09-27 |
| `nuclei.json` | https://raw.githubusercontent.com/projectdiscovery/nuclei/5b6510fb794c8805d9ad039f69f2ac134f0ff270/nuclei-jsonschema.json | MIT | `94d84a1a1e6e3fb48bae3e9f5027c62646225d99fda75e7ec8bfd422f7386f68` | 2026-09-27 |

Canonical locations: `compose-spec.json` is the schema in the Compose
Specification repo (`schema/compose-spec.json`). `github-workflow.json` is the
file served at https://json.schemastore.org/github-workflow.json. `nuclei.json`
is `nuclei-jsonschema.json` in the nuclei repo (default branch `dev`).

## Remote references

None of the three files has a `$ref` outside the file itself (every `$ref`
starts with `#`). The only URLs are the `$schema` meta-schema identifiers
(json-schema.org draft-07 / 2020-12), which the server has built in, the
`$id` values, and links inside descriptions. The server never fetches any of
them. Even if it tried, the dead-proxy setting would block the request.

## Updating

```sh
# pick the new commit, download, check, record
gh api 'repos/compose-spec/compose-spec/commits?path=schema/compose-spec.json&per_page=1' --jq '.[0].sha'
curl -fsSL -o nvim/schemas/compose-spec.json \
  https://raw.githubusercontent.com/compose-spec/compose-spec/<sha>/schema/compose-spec.json
shasum -a 256 nvim/schemas/*.json    # Debian: sha256sum
grep -o '"\$ref": *"[^#][^"]*"' nvim/schemas/*.json   # must print nothing
```

Review the diff, then update the table above (commit, sha256, date).
