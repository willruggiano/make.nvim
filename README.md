# make.nvim

Not _even_ beta-level software :)

```lua
-- Using packer.nvim
use {
  "willruggiano/make.nvim",
  config = function()
    local cwd = vim.fn.getcwd()
    require("make").setup {
      -- The argument passed to cmake via -S
      source_dir = cwd,
      -- The argument passed to cmake via -B
      binary_dir = cwd .. "/build/Debug",
      -- The argument passed to cmake via -DCMAKE_BUILD_TYPE
      build_type = "Debug",
      -- The argument passed to cmake via -G
      generator = "Ninja",

      -- The argument passed to cmake via --target
      build_target = "all",
      -- The argument passed to cmake via --parallel
      build_parallelism = 16,

      -- The path to the CMake executable
      exe = "cmake",
      -- Additional arguments passed to cmake when generating the buildsystem
      generate_arguments = { "-DENABLE_SOMETHING=ON", },
      -- Additional arguments passed to cmake when building the project
      build_arguments = {
        -- You can pass CMake arguments
        "--config RelWithDebInfo",
        -- and/or native build options (after a "--")
        "--",
        "--debug"  -- for GNU make
      },
      -- Whether to open a quickfix window when compilation/linking fails
      open_quickfix_on_error = true,
      -- The command to use to open the quickfix window
      quickfix_command = "botright cwindow",
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
" Runs cmake -S <source_dir> -B <binary_dir> -DCMAKE_BUILD_TYPE=<build_type> -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
:lua require("make").generate()
" Runs cmake --build <binary_dir> --target all --parellel <build_parallelism>
:lua require("make").compile({ build_target = "all" })
" Ditto, but does not open the quickfix window if the build fails
:lua require("make").compile({ open_quickfix_on_error = false })
" Toggles the terminal window used to run cmake command
:lua require("make").toggle()
" Shows the current make configuration (i.e. options passed to setup(...)) in a popup window
:lua require("make").info()
" Prints the exit code of the most recent make invocation
:lua require("make").status()
" Returns the current make configuration
:lua require("make").config()
" Unlinks compile_commands.json and `rm -rf` the binary_dir
:lua require("make").clean()
" Changes the build_type
:lua require("make").set_build_type("RelWithDebInfo")
" Changes the build_target
:lua require("make").set_build_target("test")
```

See [willruggiano/dotfiles#after/plugin/make.lua](https://github.com/willruggiano/dotfiles/blob/main/.config/nvim/after/plugin/make.lua)

```lua
-- makerc.lua (per project configuration, in the project root)
return function(options) -- `options` is whatever was configured via setup(...)
  return {
    -- See above for options that can be passed to setup({...})
  }
end
```
