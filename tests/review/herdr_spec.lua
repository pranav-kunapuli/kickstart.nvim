local herdr = require("review.herdr")

local LIST = vim.json.encode({ result = { agents = {
  { pane_id = "w1:p1", tab_id = "w1:t1", workspace_id = "w1", agent = "claude", agent_status = "idle", cwd = "/repo/a" },
  { pane_id = "w1:p2", tab_id = "w1:t2", workspace_id = "w1", agent = "pi", agent_status = "working", cwd = "/repo/b" },
  { pane_id = "w2:p1", tab_id = "w2:t1", workspace_id = "w2", agent = "codex", agent_status = "idle", cwd = "/elsewhere" },
} } })

--- Fake herdr that records every argv and answers `agent list` with LIST.
local function fake(code)
  local calls = {}
  return calls, function(argv)
    calls[#calls + 1] = argv
    if argv[2] == "agent" and argv[3] == "list" then
      return { code = 0, stdout = LIST, stderr = "" }
    end
    return { code = code or 0, stdout = "", stderr = code and code ~= 0 and "boom" or "" }
  end
end

local function with_env(env, fn)
  local saved = {}
  for k, v in pairs(env) do saved[k] = vim.env[k]; vim.env[k] = v end
  local ok, err = pcall(fn)
  for k in pairs(env) do vim.env[k] = saved[k] end
  if not ok then error(err) end
end

describe("herdr.agents", function()
  it("keeps only agents in this workspace", function()
    with_env({ HERDR_WORKSPACE_ID = "w1" }, function()
      local _, exec = fake()
      local agents = herdr.agents(exec)
      assert.are.equal(2, #agents)
      assert.are.same({ "w1:p1", "w1:p2" }, { agents[1].pane_id, agents[2].pane_id })
    end)
  end)

  it("reports a failed list", function()
    local agents, err = herdr.agents(function() return { code = 1, stdout = "", stderr = "not in herdr" } end)
    assert.is_nil(agents)
    assert.is_true(err:find("not in herdr", 1, true) ~= nil)
  end)
end)

describe("herdr.resolve", function()
  it("picks a lone agent", function()
    assert.are.equal("x", herdr.resolve({ { pane_id = "x" } }).pane_id)
  end)

  it("picks the lone agent sharing this tab", function()
    with_env({ HERDR_TAB_ID = "w1:t2" }, function()
      local a = herdr.resolve({ { pane_id = "a", tab_id = "w1:t1" }, { pane_id = "b", tab_id = "w1:t2" } })
      assert.are.equal("b", a.pane_id)
    end)
  end)

  it("is nil when several could be meant", function()
    with_env({ HERDR_TAB_ID = "w1:t9" }, function()
      assert.is_nil(herdr.resolve({ { pane_id = "a", tab_id = "w1:t1" }, { pane_id = "b", tab_id = "w1:t2" } }))
    end)
  end)
end)

describe("herdr.send", function()
  it("pastes without submitting", function()
    local calls, exec = fake()
    assert.is_true(herdr.send("w1:p1", "hi", false, exec))
    assert.are.same({ "herdr", "pane", "send-text", "w1:p1", "hi" }, calls[1])
  end)

  it("submits through agent prompt", function()
    local calls, exec = fake()
    herdr.send("w1:p1", "hi", true, exec)
    assert.are.same({ "herdr", "agent", "prompt", "w1:p1", "hi" }, calls[1])
  end)

  it("returns the CLI error", function()
    local _, exec = fake(1)
    local ok, err = herdr.send("w1:p1", "hi", false, exec)
    assert.is_false(ok)
    assert.is_true(err:find("boom", 1, true) ~= nil)
  end)
end)

describe("herdr.dispatch", function()
  it("sends to the agent in this tab without asking, building text from its cwd", function()
    with_env({ HERDR_WORKSPACE_ID = "w1", HERDR_TAB_ID = "w1:t2" }, function()
      local calls, exec = fake()
      local got
      herdr.dispatch(function(agent) return herdr.location("/repo/b/x.py", 3, 5, agent.cwd) end, false,
        function(agent) got = agent end, exec)
      assert.are.equal("w1:p2", got.pane_id)
      assert.are.same({ "herdr", "pane", "send-text", "w1:p2", "x.py:3-5 " }, calls[2])
    end)
  end)

  it("asks when ambiguous, and a cancelled pick sends nothing", function()
    with_env({ HERDR_WORKSPACE_ID = "w1", HERDR_TAB_ID = "w1:t9" }, function()
      local calls, exec = fake()
      local select = vim.ui.select
      local offered
      vim.ui.select = function(items, _, cb) offered = #items; cb(nil) end
      herdr.dispatch("text", true, nil, exec)
      vim.ui.select = select
      assert.are.equal(2, offered)
      assert.are.equal(1, #calls)
    end)
  end)
end)

describe("herdr.location", function()
  it("collapses a single line and keeps outside files absolute", function()
    assert.are.equal("a/b.lua:7 ", herdr.location("/r/a/b.lua", 7, 7, "/r/"))
    assert.are.equal("/x/b.lua:1-2 ", herdr.location("/x/b.lua", 1, 2, "/r"))
  end)
end)
