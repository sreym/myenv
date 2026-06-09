-- Basic settings
vim.opt.number = true           -- Show line numbers
vim.opt.expandtab = true        -- Use spaces instead of tabs
vim.opt.shiftwidth = 4          -- Indent by 2 spaces
vim.opt.tabstop = 4             -- A tab is 2 spaces
vim.opt.smartindent = true      -- Smart indentation
vim.opt.wrap = false            -- Don't wrap lines
vim.opt.termguicolors = true    -- Enable true color support
vim.opt.cursorline = true       -- Highlight current line
vim.opt.termguicolors = true
vim.o.mouse = "a"
vim.opt.clipboard = "unnamedplus"
vim.g.clipboard = 'osc52'       -- Enable global clipbaord between ssh sessions

vim.pack.add({ 'https://github.com/vague-theme/vague.nvim' })
vim.cmd.colorscheme('vague')

vim.o.list = true
vim.o.listchars = 'tab:» ,trail:•'

local function setup_trailing_whitespace()
  vim.api.nvim_set_hl(0, 'TrailingWhitespace', { bg = 'LightRed' })
end
setup_trailing_whitespace()
vim.api.nvim_create_autocmd('ColorScheme', { pattern = '*', callback = setup_trailing_whitespace })
vim.api.nvim_create_autocmd('BufEnter', {
  pattern = '*',
  command = [[
    syntax clear TrailingWhitespace |
    syntax match TrailingWhitespace "\s\+$"
  ]]}
)

vim.pack.add({ 'https://github.com/m4xshen/smartcolumn.nvim' })

vim.pack.add({
  {
    src = 'https://github.com/nvim-neo-tree/neo-tree.nvim',
    version = vim.version.range('3')
  },
  -- dependencies
  'https://github.com/nvim-lua/plenary.nvim',
  'https://github.com/MunifTanjim/nui.nvim',
  -- optional, but recommended
  'https://github.com/nvim-tree/nvim-web-devicons',
})

vim.keymap.set('n', '<leader>e', ':Neotree toggle<CR>', { silent = true })

vim.api.nvim_create_autocmd('VimEnter', {
  callback = function()
    vim.cmd([[set t_ut=]])
  end,
})

require('cvs-annotate').setup({
  enabled     = true,
  format      = ' %revision | %author | %date',
  cache_ttl   = 300,   -- 5 minutes
})

-- In your init.lua or a dedicated statusline config:
vim.o.statusline = table.concat({
  '%f',          -- filename
  ' %m%r',       -- modified/readonly flags
  '%=',          -- right-align from here
  "%{v:lua.require('cvs-annotate').get_current_line_annotation()}",
  '  %l:%c ',   -- line:col
}, '')

require('cvs-log').setup({ width = 60 })
vim.keymap.set('n', '<leader>l', ':CvsLog<CR>', { silent = true })


