-- Markdown: links, headings, rename. The only server allowed in the notes dir.
return {
  cmd = { 'marksman', 'server' },
  filetypes = { 'markdown' }, -- upstream also lists markdown.mdx, unknown to Neovim
  -- Nearest of the two wins (a ~/.marksman.toml must not swallow every repo).
  root_markers = { { '.marksman.toml', '.git' } },
}
