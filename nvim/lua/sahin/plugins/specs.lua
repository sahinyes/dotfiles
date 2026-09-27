-- Plugin list for vim.pack, dependencies first. Exact revisions live in
-- nvim-pack-lock.json (committed). Untagged plugins are frozen to a commit.
local gh = function(repo) return 'https://github.com/' .. repo end

return {
  { src = gh('nvim-lua/plenary.nvim'), name = 'plenary.nvim', version = '74b06c6c75e4eeb3108ec01852001636d85a932b' }, -- master branch (no tags); bump by editing the sha
  { src = gh('neovim/nvim-lspconfig'), name = 'nvim-lspconfig', version = vim.version.range('2.*') },
  { src = gh('nvim-telescope/telescope.nvim'), name = 'telescope.nvim', version = vim.version.range('0.2.*') },
  { src = gh('lewis6991/gitsigns.nvim'), name = 'gitsigns.nvim', version = vim.version.range('2.*') },
  { src = gh('nvim-mini/mini.nvim'), name = 'mini.nvim', version = 'stable' },
  {
    src = gh('nvim-treesitter/nvim-treesitter'),
    name = 'nvim-treesitter',
    version = '728e031f6b11d03d1f0708b7dc4fb0f1d9c8a137',
  }, -- main branch (no tags); bump by editing the sha
  {
    src = gh('MeanderingProgrammer/render-markdown.nvim'),
    name = 'render-markdown.nvim',
    version = vim.version.range('8.*'),
  },
  { src = gh('tris203/precognition.nvim'), name = 'precognition.nvim', version = 'v1.3.0' },
}
