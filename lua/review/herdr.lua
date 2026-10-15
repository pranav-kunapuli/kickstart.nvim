--- Hand text straight to an agent pane through the herdr CLI, so a review
--- round doesn't need a clipboard hop. `exec` is injectable for tests.
local M = {}

function M.exec(argv)
  local ok, proc = pcall(vim.system, argv, { text = true })
  if not ok then return { code = -1, stdout = "", stderr = tostring(proc) } end
  local r = proc:wait()
  return { code = r.code, stdout = r.stdout or "", stderr = r.stderr or "" }
end

local function failed(what, r)
  return what .. " failed: " .. (r.stderr ~= "" and vim.trim(r.stderr) or ("exit " .. r.code))
end

--- Agents in this herdr workspace, or nil and an error outside herdr.
function M.agents(exec)
  exec = exec or M.exec
  local r = exec({ "herdr", "agent", "list" })
  if r.code ~= 0 then return nil, failed("herdr agent list", r) end
  local ok, decoded = pcall(vim.json.decode, r.stdout)
  if not ok or type(decoded) ~= "table" then return nil, "herdr agent list: unparseable JSON" end
  local workspace = vim.env.HERDR_WORKSPACE_ID
  local out = {}
  for _, a in ipairs((decoded.result or {}).agents or {}) do
    if not workspace or a.workspace_id == workspace then
      out[#out + 1] = {
        pane_id = a.pane_id,
        tab_id = a.tab_id,
        kind = a.agent or "agent",
        status = a.agent_status or "unknown",
        cwd = a.cwd or "",
        title = a.terminal_title_stripped or a.terminal_title or a.agent or "agent",
      }
    end
  end
  table.sort(out, function(x, y) return x.pane_id < y.pane_id end)
  return out
end

--- The one agent the text is obviously meant for, or nil when it's ambiguous:
--- a lone agent in the workspace, else a lone agent sharing this tab.
function M.resolve(agents)
  if #agents == 1 then return agents[1] end
  local tab = vim.env.HERDR_TAB_ID
  if not tab then return nil end
  local in_tab = vim.tbl_filter(function(a) return a.tab_id == tab end, agents)
  return #in_tab == 1 and in_tab[1] or nil
end

function M.describe(agent)
  return ("%s · %s · %s · %s"):format(agent.kind, agent.status, vim.fn.fnamemodify(agent.cwd, ":t"), agent.title)
end

--- `submit` presses Enter for you; otherwise the text lands in the input
--- for you to finish or edit.
function M.send(pane_id, text, submit, exec)
  exec = exec or M.exec
  local argv = submit and { "herdr", "agent", "prompt", pane_id, text }
    or { "herdr", "pane", "send-text", pane_id, text }
  local r = exec(argv)
  if r.code ~= 0 then return false, failed(table.concat(argv, " ", 1, 3), r) end
  return true
end

--- `file` shortened against the agent's cwd; a file outside it stays absolute,
--- the only spelling that still resolves from there.
--- Both sides go through realpath first: git reports resolved paths while a
--- shell cwd can sit behind a symlink (/var vs /private/var on macOS).
function M.relpath(file, cwd)
  if not cwd or cwd == "" then return file end
  for _, candidate in ipairs({ cwd, vim.uv.fs_realpath(cwd) }) do
    local prefix = candidate:gsub("/$", "") .. "/"
    for _, path in ipairs({ file, vim.uv.fs_realpath(file) }) do
      if path:sub(1, #prefix) == prefix then return path:sub(#prefix + 1) end
    end
  end
  return file
end

--- `path:12` or `path:12-20`, plus a trailing space so the sentence carries on.
function M.location(file, first, last, cwd)
  local path = M.relpath(file, cwd)
  if first == last then return ("%s:%d "):format(path, first) end
  return ("%s:%d-%d "):format(path, first, last)
end

--- Resolve the target (asking only when ambiguous), then send. `text` may be
--- a function of the agent, for text that depends on its cwd.
--- on_done(agent) runs after a successful send.
function M.dispatch(text, submit, on_done, exec)
  local util = require("review.util")
  local agents, err = M.agents(exec)
  if not agents then
    util.notify(err, vim.log.levels.ERROR)
    return
  end
  if #agents == 0 then
    util.notify("no agents in this herdr workspace", vim.log.levels.WARN)
    return
  end
  local function go(agent)
    if not agent then return end
    local payload = type(text) == "function" and text(agent) or text
    local ok, send_err = M.send(agent.pane_id, payload, submit, exec)
    if not ok then
      util.notify(send_err, vim.log.levels.ERROR)
      return
    end
    if on_done then on_done(agent) end
  end
  local target = M.resolve(agents)
  if target then return go(target) end
  vim.ui.select(agents, { prompt = "Send to agent", format_item = M.describe }, go)
end

return M
