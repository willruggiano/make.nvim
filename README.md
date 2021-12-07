# make.nvim

Not _even_ beta-level software :)

```lua
-- Using packer.nvim
use {
  "willruggiano/make.nvim",
  config = function()
    require("make").setup {
      -- The name of the "default" profile
      default_profile = "default",
      -- Default profile specification
      default = {
        -- The argument passed to cmake via -S
        source_dir = <path>,
        -- The argument passed to cmake via -B
        binary_dir = <path>,

        -- The argument passed to cmake via -DCMAKE_BUILD_TYPE
        build_type = <cmake build type>,
        -- The argument passed to cmake via -G
        generator = <cmake build system generator>,
        -- Additional arguments passed to cmake when generating the buildsystem
        generate_arguments = <table>,

        -- The argument passed to cmake via --target
        build_target = <cmake build target>,
        -- The argument passed to cmake via --parallel
        build_parallelism = <int>,
        -- Additional arguments passed to cmake when building the project
        -- Pass native build options after a "--"
        build_arguments = <table>,

        -- The path to the CMake executable
        exe = "cmake",
        -- Whether to (re)generate the build system after switching profiles
        generate_after_profile_switch = true,
        -- Whether to open a quickfix window when compilation/linking fails
        open_quickfix_on_error = true,
        -- The command to use to open the quickfix window
        quickfix_command = "botright cwindow",
      },
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
" Prints the current (i.e. current profile) make configuration
:lua require("make").info()
" Prints the exit code of the most recent make invocation
:lua require("make").status()
" Returns the current (i.e. current profile) make configuration
:lua require("make").config()
" Unlinks compile_commands.json and `rm -rf` the binary_dir
:lua require("make").clean()
" Changes the build_type
:lua require("make").set_build_type("RelWithDebInfo")
" Changes the build_target
:lua require("make").set_build_target("test")
" Switches the current profile
:lua require("make").switch_profile({ profile = "debug" })
" Prints the make configuration for a specific profile
:lua require("make").show_profile("debug")
```

See [willruggiano/dotfiles#make.lua](https://github.com/willruggiano/dotfiles/blob/main/.config/nvim/lua/bombadil/config/make.lua)

```lua
-- makerc.lua (per project configuration, in the project root)
return function(options) -- `options` is whatever was configured via setup(...)
  return {
    -- Override the default profile specification
    <default profile name> = <table>,
    -- Add additional, project specific profiles
    <additional profile name> = <table>,
  }
end
```
