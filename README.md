# make.nvim

Not *even* beta-level software :)

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
      window = {
        winblend = 15,
        percentage = 0.9,
      },
    }
  end,
  requires = "nvim-lua/plenary.nvim",
  rocks = "luafilesystem",
}
```

```vim
:lua require("make").generate()
:lua require("make").compile("all")
```
