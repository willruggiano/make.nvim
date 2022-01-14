local lfs = require "lfs"
local has_notify, notify = pcall(require, "notify")
local job_ctrl = require "firvish.job_control"

local defaults = {
  -- The CMake command to run
  exe = "cmake",
  -- Whether to (re)generate the buildsystem after switching profiles
  generate_after_profile_switch = true,
  -- Whether to open the quickfix window on build failure
  open_quickfix_on_error = true,
  -- The command to use to open the quickfix window
  quickfix_command = "botright cwindow",
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

M.generate = function(opts, force)
  local options = override_config(opts)
  if not check_config(options) then
    return
  end
  local cmd = {
    options.exe,
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
      cmd[#cmd + 1] = i
    end
  end

  if force then
    os.execute("rm " .. options.binary_dir .. "/CMakeCache.txt")
  end

  job_ctrl.start_job {
    cmd = cmd,
    filetype = "log",
    title = "cmake-generate",
    listed = true,
    on_exit = function(_, exit_code, _)
      if exit_code == 0 then
        link_compile_commands()
      end
    end,
    output_qf = true,
    is_background_job = false,
    cwd = vim.fn.getcwd(),
  }
end

M.link_compile_commands = link_compile_commands

M.compile = function(opts)
  local options = override_config(opts)
  if not check_config(options) then
    return
  end
  if vim.fn.isdirectory(options.binary_dir) == 0 then
    show_notification("you must run generate() before compile()", "error", { title = "make.nvim" })
    return
  end
  local cmd = {
    options.exe,
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
      cmd[#cmd + 1] = i
    end
  end

  job_ctrl.start_job {
    cmd = cmd,
    filetype = "log",
    title = "cmake-build",
    listed = true,
    output_qf = true,
    is_background_job = false,
    cwd = vim.fn.getcwd(),
  }
end

M.clean = function()
  if not check_config() then
    return
  end
  if not os.remove(current.source_dir .. "/compile_commands.json") then
    show_notification("failed to remove compile_commands.json", "error", { title = "make.nvim" })
  end
  if os.execute("rm -rf " .. current.binary_dir) ~= 0 then
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
  show_notification(
    "make.toggle() is deprecated. Please use firvish's job-list instead",
    "error",
    { title = "make.nvim" }
  )
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
