--- LSP jumps that stay inside the diffview tab. A target in a changed file
--- switches diffview to that entry; anything else opens in a new tab so the
--- diff layout survives. <C-t> walks back through the jumps made here.
local dv = require("review.dv")
local util = require("review.util")

local M = {}

--- @type { entry: table, line: integer, col: integer }[]
local back_stack = {}

local function normalize(path)
  return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

--- The working-tree entry wins when a file is both staged and unstaged: it is
--- the one whose new side is the live file the LSP answered about.
local function entry_for(view, absolute_path)
  local root = dv.repo_root()
  if not root then return nil end
  root = normalize(root)
  local target = normalize(absolute_path)
  if target:sub(1, #root + 1) ~= root .. "/" then return nil end
  local relative = target:sub(#root + 2)

  local found
  for _, entry in view.files:iter() do
    if entry.path == relative then
      if entry.kind == "working" then return entry end
      found = found or entry
    end
  end
  return found
end

local function place_cursor(window, line, col)
  vim.api.nvim_set_current_win(window)
  pcall(vim.api.nvim_win_set_cursor, window, { line, col })
  vim.cmd("normal! zz")
end

--- set_file is async and returns before the new buffers are in their windows,
--- so wait for the entry to land before moving the cursor.
local function show_entry(view, entry, line, col)
  if view.cur_entry == entry then
    place_cursor(view.cur_layout:get_main_win().id, line, col)
    return
  end
  view:set_file(entry, true, true)
  local deadline = vim.uv.now() + 2000
  local function poll()
    local layout = view.cur_entry == entry and view.cur_layout
    local main = layout and layout:get_main_win()
    if main and main.file and main.file.bufnr
        and vim.api.nvim_win_is_valid(main.id)
        and vim.api.nvim_win_get_buf(main.id) == main.file.bufnr then
      place_cursor(main.id, line, col)
    elseif vim.uv.now() < deadline then
      vim.defer_fn(poll, 20)
    else
      util.notify("timed out opening " .. entry.path, vim.log.levels.WARN)
    end
  end
  poll()
end

local function remember_position(view)
  local cursor = vim.api.nvim_win_get_cursor(0)
  back_stack[#back_stack + 1] = { entry = view.cur_entry, line = cursor[1], col = cursor[2] }
end

local function go(view, item)
  local line, col = item.lnum, math.max((item.col or 1) - 1, 0)
  local entry = entry_for(view, item.filename)
  if entry then
    remember_position(view)
    show_entry(view, entry, line, col)
    return
  end
  vim.cmd.tabedit(vim.fn.fnameescape(item.filename))
  pcall(vim.api.nvim_win_set_cursor, 0, { line, col })
  vim.cmd("normal! zz")
end

--- Go to definition without leaving diffview.
--- @return boolean handled false when the current buffer is not a diff buffer
function M.definition()
  local view = dv.view()
  if not view or not dv.locate(vim.api.nvim_get_current_buf()) then return false end

  vim.lsp.buf.definition({
    on_list = function(result)
      local items = result.items
      if #items == 0 then
        util.notify("no definition found")
      elseif #items == 1 then
        go(view, items[1])
      else
        vim.ui.select(items, {
          prompt = "Definitions",
          format_item = function(item)
            return ("%s:%d  %s"):format(vim.fn.fnamemodify(item.filename, ":~:."), item.lnum, vim.trim(item.text or ""))
          end,
        }, function(item)
          if item then go(view, item) end
        end)
      end
    end,
  })
  return true
end

function M.back()
  local view = dv.view()
  local previous = table.remove(back_stack)
  if not view or not previous then
    util.notify("no earlier definition jump")
    return
  end
  show_entry(view, previous.entry, previous.line, previous.col)
end

return M
