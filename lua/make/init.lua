local lfs = require "lfs"
local has_notify, notify = pcall(require, "notify")
local Terminal = require("toggleterm.terminal").Terminal

local defaults = {
  -- The CMake command to run
  exe = "cmake",
  -- Whether to (re)generate the buildsystem after switching profiles
  generate_after_profile_switch = true,
  -- Whether to open the quickfix window on build failure
  open_quickfix_on_error = true,
  -- The command to use to open the quickfix window
  quickfix_command = "botright cwindow",
  -- NOTE: See akinsho/nvim-toggleterm.lua for term options
  term = {
    direction = "float",
    float_opts = {
      winblend = 3,
      highlights = {
        background = "Normal",
        border = "Normal",
      },
    },
  },
}
local required_config_options = {
  "exe",
  "source_dir",
  "binary_dir",
  "build_type",
  "build_parallelism",
  "generator",
}

local config = {}
local current = {}
local context = {}

local show_notification = function(...)
  if has_notify then
    notify(...)
  else
    local args = { ... }
    print("[make.nvim] " .. args[1])
  end
end

local check_config_option = function(cfg, key)
  if cfg[key] == nil then
    show_notification(string.format("%s is a required configuration option", key), "error", { title = "make.nvim" })
    return false
  end
  return true
end

local check_config = function(cfg)
  cfg = cfg or current
  local ok = true
  for _, k in ipairs(required_config_options) do
    if not check_config_option(cfg, k) then
      ok = false
    end
  end
  return ok
end

local override_config = function(opts)
  return vim.tbl_deep_extend("force", current, opts or {})
end

local filter_qf_list = function(list)
  local items = {}
  for _, e in ipairs(list.items) do
    if e.valid == 1 then
      items[#items + 1] = e
    end
  end
  list.items = items
  return list, #items
end

-- TODO: A couple things.
--  * Filter identical error messages? Or *allow* the user to do so via some setup option
--  * Provide a mechanism by which you can see the error context (e.g. "in file included from",
--    template backtraces, etc)
--  * Set the height of the quickfix popup in a manner similar to how we compute the window size
local set_qf_list = function(term, open)
  check_config_option(current, "quickfix_command")
  local lines = vim.api.nvim_buf_get_lines(term.bufnr, 0, -1, false)
  local list, count = filter_qf_list(vim.fn.getqflist { lines = lines })
  show_notification("added " .. count .. " items to the quickfix list", "info", { title = "make.nvim" })
  vim.fn.setqflist({}, " ", list)
  if open == true then
    term:close()
    vim.cmd(current.quickfix_command)
  end
end

local link_compile_commands = function(overwrite)
  local target = current.binary_dir .. "/compile_commands.json"
  local link_name = current.source_dir .. "/compile_commands.json"
  if overwrite then
    os.remove(link_name)
  end
  lfs.link(target, link_name, true)
end

local load_makerc = function()
  local package_path = package.path
  package.path = "?.lua"
  local ok, makerc = pcall(require, "makerc")
  package.path = package_path
  return ok, makerc
end

local M = {}

M.generate = function(opts)
  local options = override_config(opts)
  if not check_config(options) then
    return
  end
  local args = {
    "-S",
    options.source_dir,
    "-B",
    options.binary_dir,
    "-G",
    options.generator,
    "-DCMAKE_BUILD_TYPE=" .. options.build_type,
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
  }
  local user_args = options.generate_arguments or {}
  if #user_args > 0 then
    for _, i in ipairs(user_args) do
      args[#args + 1] = i
    end
  end

  local term = Terminal:new {
    cmd = options.exe .. " " .. table.concat(args, " "),
    dir = options.source_dir,
    on_exit = function(self, _, code, signal)
      if code ~= 0 then
        show_notification(
          string.format(":MakeGenerate failed! [c:%s,s:%s]", code, signal),
          "error",
          { title = "make.nvim" }
        )
      else
        link_compile_commands(true)
        self:toggle()
        show_notification(":MakeGenerate succeeded!", "info", { title = "make.nvim" })
      end
      context.status = code
    end,
    close_on_exit = false,
    direction = options.term.direction,
    float_opts = options.term.float_opts,
    hidden = true,
    start_in_insert = false,
  }
  term:toggle()
  context.previous = term
end

M.compile = function(opts)
  local options = override_config(opts)
  if not check_config(options) then
    return
  end
  if vim.fn.isdirectory(options.binary_dir) == 0 then
    show_notification("you must run generate() before compile()", "error", { title = "make.nvim" })
    return
  end
  local args = {
    "--build",
    options.binary_dir,
    "--target",
    options.build_target,
    "--parallel",
    options.build_parallelism,
  }
  local make_args = options.build_arguments or {}
  if #make_args > 0 then
    for _, i in ipairs(make_args) do
      args[#args + 1] = i
    end
  end

  local term = Terminal:new {
    cmd = options.exe .. " " .. table.concat(args, " "),
    dir = options.source_dir,
    on_open = function()
      vim.cmd "cclose"
    end,
    on_exit = function(self, _, code)
      if code ~= 0 then
        show_notification(string.format("error building %s", options.build_target), "error", { title = "make.nvim" })
        vim.schedule(function()
          set_qf_list(self, options.open_quickfix_on_error)
        end)
      else
        self:close()
        show_notification(string.format("built %s successfully", options.build_target), "info", { title = "make.nvim" })
      end
      context.status = code
    end,
    close_on_exit = false,
    direction = options.term.direction,
    float_opts = options.term.float_opts,
    hidden = true,
    start_in_insert = false,
  }
  term:toggle()
  context.previous = term
end

M.clean = function()
  if not check_config() then
    return
  end
  if not os.remove(current.source_dir .. "/compile_commands.json") then
    show_notification("failed to remove compile_commands.json", "error", { title = "make.nvim" })
  end
  if os.execute("rm -rf " .. config.binary_dir) ~= 0 then
    show_notification("failed to remove build directory", "error", { title = "make.nvim" })
  end
end

M.set_build_target = function(build_target)
  current = override_config { build_target = build_target }
end

M.set_build_type = function(build_type)
  local previous_build_type = current.build_type
  if previous_build_type ~= build_type then
    current = override_config {
      binary_dir = string.gsub(current.binary_dir, previous_build_type, build_type),
      build_type = build_type,
    }
    M.generate()
  end
end

M.show_profile = function(name)
  local profile = config[name]
  if profile ~= nil then
    print(vim.inspect(profile))
  end
end

M.switch_profile = function(opts)
  local profile = config[opts.profile]
  assert(profile ~= nil, "profile does not exist")
  current = override_config(profile)
  M.generate()
end

M.info = function()
  if not check_config() then
    return
  end
  print(vim.inspect(current))
end

M.status = function()
  if context.status ~= nil then
    print("Last job exited with status:", context.status)
  end
end

M.config = function()
  return config
end

M.active = function()
  return current
end

M.toggle = function()
  local term = context.previous
  -- TODO: Figure out how to toggle. Currently, toggling will re-execute the cmd we created the
  -- Terminal with.
  if not term then
    show_notification(
      "no previous terminal to toggle, run generate() or compile() first",
      "error",
      { title = "make.nvim" }
    )
  else
    term:toggle()
  end
end

M.setup = function(opts)
  local default_profile = opts.default_profile or "default"
  config = vim.tbl_deep_extend("force", { [default_profile] = defaults }, opts)
  local ok, generator = load_makerc()
  if ok then
    config = vim.tbl_deep_extend("force", config, generator(config))
  end
  current = config[default_profile]
end

return M
