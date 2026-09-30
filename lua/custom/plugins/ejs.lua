-- EJS files use the embedded_template parser, which nvim-treesitter installs
-- from its own parser list (see the treesitter spec in init.lua).
vim.filetype.add { extension = { ejs = 'embedded_template' } }

return {}
