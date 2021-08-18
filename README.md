# make.nvim

Not _even_ beta-level software :)

```lua
-- Using packer.nvim
use {
  "make.nvim",
  config = function()
    local cwd = vim.fn.getcwd()
    require("make").setup {
      exe = "cmake",
      source_dir = cwd,
      binary_dir = cwd .. "/build/Debug",
      build_type = "Debug",
      build_target = "all",
      build_parallelism = 16,
      generator = "Ninja",
      open_quickfix_on_error = true,
    }
  end,
  requires = {
    "nvim-lua/plenary.nvim",
    "rcarriga/nvim-notify",
    "akinsho/nvim-toggleterm.lua",
  },
  rocks = "luafilesystem",
}
```

```vim
:lua require("make").generate()
:lua require("make").compile({ build_target = "all" })
:lua require("make").compile({ open_quickfix_on_error = false })
```
