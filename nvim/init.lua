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

vim.pack.add({ 'https://github.com/vague-theme/vague.nvim' })
vim.cmd.colorscheme('vague')

vim.pack.add({
  {
    src = 'https://github.com/nvim-neo-tree/neo-tree.nvim',
    version = vim.version.range('3')
  },
  -- dependencies
  "https://github.com/nvim-lua/plenary.nvim",
  "https://github.com/MunifTanjim/nui.nvim",
  -- optional, but recommended
  "https://github.com/nvim-tree/nvim-web-devicons",
})

vim.keymap.set('n', '<leader>e', ':Neotree toggle<CR>', { silent = true })

vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        vim.cmd([[set t_ut=]])
    end,
})

