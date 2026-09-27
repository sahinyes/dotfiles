-- netrw's "Network" augroup reads, writes and sources scp:// sftp:// ftp://
-- rsync:// dav:// file:// names by running scp/curl/... through the shell.
-- Nothing here edits remote files, so opening such a name (a link in a log,
-- a crafted argument) must not start a process. Local browsing (:Explore,
-- FileExplorer augroup) keeps working. nvu never loads netrw at all.
pcall(vim.api.nvim_del_augroup_by_name, 'Network')
