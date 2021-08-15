local Job = require "plenary.job"
local tbl = require "plenary.tbl"
local lfs = require "lfs"

local config = {
  window = {
    cursorcolumn = false,
    percentage = 0.9,
    relative = "editor",
    style = "minimal",
    winblend = 15,
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

local default_win_opts = function()
  local options = config.window

  local width = math.floor(vim.o.columns * options.percentage)
  local height = math.floor(vim.o.lines * options.percentage)

  local top = math.floor(((vim.o.lines - height) / 2) - 1)
  local left = math.floor((vim.o.columns - width) / 2)

  return {
    relative = options.relative,
    row = top,
    col = left,
    width = width,
    height = height,
    style = options.style,
  }
end

local apply_default_win_opts = function(win_id)
  vim.api.nvim_win_set_option(win_id, "cursorcolumn", config.window.cursorcolumn)
  vim.api.nvim_win_set_option(win_id, "winblend", config.window.winblend)
end

local create_buffer = function()
  local buffer = context.buffer
  if buffer ~= nil then
    -- Only keep one buffer around
    vim.api.nvim_buf_delete(buffer, { force = true })
  end
  buffer = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buffer, "filetype", "term")
  context.buffer = buffer
  return buffer
end

local create_window = function(bufnr)
  local opts = default_win_opts()
  local window = vim.api.nvim_open_win(bufnr, true, opts)
  apply_default_win_opts(window)
  context.window = window
  vim.cmd [[autocmd WinLeave ++once lua require("make").au_winleave()]]
  return window
end

local open_win = function()
  local buffer = context.buffer
  if buffer ~= nil then
    return create_window(buffer)
  else
    error "[make.nvim] cannot open window before creating buffer!"
  end
end

local toggle_term = function()
  local buffer = context.buffer
  if buffer ~= nil then
    local window = context.window
    if window ~= nil then
      -- Then we are hiding the window
      vim.api.nvim_win_hide(window)
      context.window = nil
    else
      -- Then we are opening the window
      create_window(buffer)
    end
  else
    print "[make.nvim] you must run :MakeGenerate or :Make before :MakeToggle"
  end
end

local filter_qf_list = function(list)
  local items = {}
  for _, e in ipairs(list.items) do
    if e.valid == 1 then
      table.insert(items, e)
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
local set_qf_list = function(open)
  local lines = vim.api.nvim_buf_get_lines(context.buffer, 0, -1, false)
  local list, count = filter_qf_list(vim.fn.getqflist { lines = lines })
  print("added " .. count .. " items to the quickfix list")
  vim.fn.setqflist({}, " ", list)
  if open == true then
    vim.cmd "copen"
  end
end

local link_compile_commands = function()
  local target = config.binary_dir .. "/compile_commands.json"
  local link_name = config.source_dir .. "/compile_commands.json"
  lfs.link(target, link_name, true)
end

local check_config_option = function(key)
  if config[key] == nil then
    print(string.format("[make.nvim] %s is a required configuration option", key))
    return false
  end
  return true
end

local check_config = function()
  local ok = true
  for _, k in ipairs(required_config_options) do
    if not check_config_option(k) then
      ok = false
    end
  end
  return ok
end

local M = {}

M.au_winleave = function()
  context.window = nil
end

M.generate = function()
  if not check_config() then
    return
  end
  -- TODO: Per-project arguments
  local args = {
    "-S",
    config.source_dir,
    "-B",
    config.binary_dir,
    "-G",
    config.generator,
    "-DCMAKE_BUILD_TYPE=" .. config.build_type,
    "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON",
  }

  local bufnr = create_buffer()
  local job = Job:new {
    command = config.exe,
    args = args,
    cwd = config.source_dir,
    enable_handlers = true,
    on_stdout = function(_, data)
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { data })
      end)
    end,
    on_stderr = function(_, data)
      print "on_stderr!"
    end,
    on_exit = function(_, code, signal)
      if code ~= 0 then
        print(string.format("[make.nvim] :MakeGenerate failed! [c:%s,s:%s]", code, signal))
      else
        link_compile_commands()
        print "[make.nvim] :MakeGenerate succeeded!"
      end
    end,
  }
  job:start()

  open_win()

  context.previous = job
end

M.compile = function(target)
  if not check_config() then
    return
  end
  target = target or config.build_target
  -- TODO: Per-project arguments
  local args = {
    "--build",
    config.binary_dir,
    "--target",
    target,
    "--parallel",
    config.build_parallelism,
  }
  local bufnr = create_buffer()
  local job = Job:new {
    command = config.exe,
    args = args,
    cwd = config.source_dir,
    enable_handlers = true,
    on_stdout = function(_, data)
      vim.schedule(function()
        vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, { data })
      end)
    end,
    on_stderr = function(_, data)
      print "on_stderr!"
    end,
    on_exit = function(_, code)
      if code ~= 0 then
        print(string.format("[make.nvim] error building %s", target))
        vim.schedule(function()
          set_qf_list(config.open_quickfix_on_error)
        end)
      else
        print(string.format("[make.nvim] built %s successfully", target))
      end
    end,
  }
  job:start()

  open_win()

  context.previous = job
end

M.clean = function()
  if not check_config() then
    return
  end
  if not os.remove(config.source_dir .. "/compile_commands.json") then
    print "[make.nvim] failed to remove compile_commands.json"
  end
  if os.execute("rm -rf " .. config.binary_dir) ~= 0 then
    print "[make.nvim] failed to remove build directory"
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
  toggle_term()
end

-- TODO: Per-project configuration
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts)
end

return M
