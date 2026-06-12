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

vim.pack.add({ 'https://github.com/m4xshen/smartcolumn.nvim' })

vim.pack.add({ 'https://codeberg.org/andyg/leap.nvim' })
vim.keymap.set({ 'n', 'x', 'o' }, 's', '<Plug>(leap)')
vim.keymap.set('n',               'S', '<Plug>(leap-from-window)')

vim.pack.add({
  {
    src = 'https://github.com/nvim-neo-tree/neo-tree.nvim',
    version = vim.version.range('3'),
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

require('cvs-log').setup({ width = 60 })
vim.keymap.set('n', '<leader>l', ':CvsLog<CR>', { silent = true })

-- statusline (using lualine)
vim.o.showmode = false      -- lualine shows mode already
vim.o.cmdheight = 0         -- hide command line when not in use
vim.pack.add({ 'https://github.com/nvim-lualine/lualine.nvim' })
require('lualine').setup {
  options = {
    icons_enabled = true,
    theme = 'auto',
    component_separators = { left = '', right = ''},
    section_separators = { left = '', right = ''},
    disabled_filetypes = {
      statusline = {},
      winbar = {},
    },
    ignore_focus = {},
    always_divide_middle = true,
    always_show_tabline = true,
    globalstatus = false,
    refresh = {
      statusline = 1000,
      tabline = 1000,
      winbar = 1000,
      refresh_time = 16, -- ~60fps
      events = {
        'WinEnter',
        'BufEnter',
        'BufWritePost',
        'SessionLoadPost',
        'FileChangedShellPost',
        'VimResized',
        'Filetype',
        'CursorMoved',
        'CursorMovedI',
        'ModeChanged',
      },
    }
  },
  sections = {
    lualine_a = {'mode'},
    lualine_b = {'branch', 'diff', 'diagnostics'},
    lualine_c = {
      'filename',
      {
        function() return require('cvs-annotate').get_current_line_annotation() end,
        cond = function() return require('cvs-annotate').config.enabled end,
      },
    },
    lualine_x = {'encoding', 'fileformat', 'filetype'},
    lualine_y = {'progress'},
    lualine_z = {'location'}
  },
  inactive_sections = {
    lualine_a = {},
    lualine_b = {},
    lualine_c = {'filename'},
    lualine_x = {'location'},
    lualine_y = {},
    lualine_z = {}
  },
  tabline = {},
  winbar = {},
  inactive_winbar = {},
  extensions = {}
}

