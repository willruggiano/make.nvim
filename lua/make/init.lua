local lfs = require "lfs"
local has_notify, notify = pcall(require, "notify")
local Terminal = require("toggleterm.terminal").Terminal

local config = {
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
local context = {}

local show_notification = function(...)
  if has_notify then
    notify(...)
  else
    local args = { ... }
    print("[make.nvim] " .. args[1])
  end
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
  local lines = vim.api.nvim_buf_get_lines(term.bufnr, 0, -1, false)
  local list, count = filter_qf_list(vim.fn.getqflist { lines = lines })
  show_notification("added " .. count .. " items to the quickfix list", "info", { title = "make.nvim" })
  vim.fn.setqflist({}, " ", list)
  if open == true then
    term:close()
    vim.cmd "copen"
  end
end

local link_compile_commands = function()
  local target = config.binary_dir .. "/compile_commands.json"
  local link_name = config.source_dir .. "/compile_commands.json"
  lfs.link(target, link_name, true)
end

local check_config_option = function(cfg, key)
  if cfg[key] == nil then
    show_notification(string.format("%s is a required configuration option", key), "error", { title = "make.nvim" })
    return false
  end
  return true
end

local check_config = function(cfg)
  cfg = cfg or config
  local ok = true
  for _, k in ipairs(required_config_options) do
    if not check_config_option(cfg, k) then
      ok = false
    end
  end
  return ok
end

local override_config = function(opts)
  return vim.tbl_deep_extend("force", config, opts or {})
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
        link_compile_commands()
        self:toggle()
        show_notification(":MakeGenerate succeeded!", "info", { title = "make.nvim" })
      end
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
  if not os.remove(config.source_dir .. "/compile_commands.json") then
    show_notification("failed to remove compile_commands.json", "error", { title = "make.nvim" })
  end
  if os.execute("rm -rf " .. config.binary_dir) ~= 0 then
    show_notification("failed to remove build directory", "error", { title = "make.nvim" })
  end
end

M.set_build_target = function(build_target)
  config.build_target = build_target
end

M.set_build_type = function(build_type)
  local previous_build_type = config.build_type
  config.build_type = build_type
  if previous_build_type ~= build_type then
    config.binary_dir = config.source_dir .. "/build/" .. build_type
    M.generate()
  end
end

M.info = function()
  if not check_config() then
    return
  end
  print(vim.inspect(config))
end

M.toggle = function()
  local term = context.term
  -- TODO: Figure out how to toggle. Currently, toggling will re-execute the cmd we created the
  -- Terminal with.
  if not term then
    show_notification("toggling the make terminal open is not currently supported", "error", { title = "make.nvim" })
  else
    show_notification("toggling the make terminal closed is not currently supported", "error", { title = "make.nvim" })
  end
end

M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts)
  local ok, generator = pcall(require, "makerc")
  if ok then
    config = vim.tbl_deep_extend("force", config, generator(config))
  end
end

return M
