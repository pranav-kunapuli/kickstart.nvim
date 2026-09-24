-- diffview registers :DiffviewOpen from setup(), not a plugin/ file
require("diffview").setup({})

local dv = require("review.dv")
local registry = require("review.registry")
local render = require("review.render")
local session = require("review.session")
local ui = require("review.ui")
local util = require("review.util")

local SRC = table.concat({
  "import os",
  "",
  "",
  "def total(awards):",
  "    total = 0",
  "    for award in awards:",
  "        s = fetch(award.id)",
  "        total += s.amount",
  "    return total",
}, "\n") .. "\n"

local function sh(root, cmd)
  return vim.system({ "bash", "-lc", cmd }, { cwd = root, text = true }):wait()
end

local function write(path, content)
  local f = assert(io.open(path, "w"))
  f:write(content)
  f:close()
end

--- A repo with two commits, plus an uncommitted edit so the new side of a
--- plain :DiffviewOpen is a real working-tree buffer.
local function mkrepo()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  sh(root, "git init -q -b main .")
  write(root .. "/award.py", SRC)
  sh(root, "git add -A && git -c user.email=t@t -c user.name=t commit -qm one")
  write(root .. "/award.py", SRC .. "\n\ndef added():\n    return 2\n")
  sh(root, "git add -A && git -c user.email=t@t -c user.name=t commit -qm two")
  write(root .. "/award.py", SRC .. "\n\ndef added():\n    return 3\n")
  return root
end

local function open_diff(root, args)
  vim.cmd("lcd " .. root)
  vim.cmd("DiffviewOpen " .. (args or ""))
  local ready = vim.wait(20000, function()
    local v = dv.view()
    local e = v and v.cur_entry
    return e ~= nil and e.layout ~= nil
      and e.layout.b and e.layout.b.file and e.layout.b.file.bufnr
      and e.layout.a and e.layout.a.file and e.layout.a.file.bufnr
  end, 100)
  assert.is_true(ready, "diffview never produced buffers for: " .. tostring(args))
  -- Buffers exist before the async layout finishes; closing mid-flight makes
  -- diffview's own coroutines fail on windows we already destroyed.
  vim.wait(400)
  return dv.view()
end

local function close_diff()
  session.detach_all()
  pcall(vim.cmd, "DiffviewClose")
  vim.wait(400) -- let diffview's async pipeline drain before the next open
end

describe("integration", function()
  local root, compose

  before_each(function()
    registry.path = vim.fn.tempname() .. "/sessions.json"
    root = mkrepo()
    compose = ui.compose
  end)

  after_each(function()
    ui.compose = compose
    close_diff()
  end)

  describe("diffview resolution", function()
    it("reads the new side as a live file and the old side as frozen", function()
      local v = open_diff(root)
      local new = dv.locate(v.cur_entry.layout.b.file.bufnr)
      assert.is_not_nil(new)
      assert.equals("new", new.side)
      assert.equals("award.py", new.path)
      assert.is_false(new.frozen)

      local old = dv.locate(v.cur_entry.layout.a.file.bufnr)
      assert.equals("old", old.side)
      assert.is_true(old.frozen)
      assert.is_true(dv.is_live())
    end)

    it("reports a commit-range diff as frozen so re-anchoring is not promised", function()
      open_diff(root, "HEAD~1..HEAD")
      assert.is_false(dv.is_live(), "HEAD~1..HEAD should have no live side")
    end)

    it("returns nil for a buffer that is not part of the diff", function()
      open_diff(root)
      local scratch = vim.api.nvim_create_buf(false, true)
      assert.is_nil(dv.locate(scratch))
    end)
  end)

  describe("capturing a comment", function()
    local function seed(range, body, tag)
      local v = open_diff(root)
      local bufnr = v.cur_entry.layout.b.file.bufnr
      vim.api.nvim_set_current_buf(bufnr)
      local s = session.attach()
      session.check_live(s)
      ui.compose = function(_, cb) cb(body or "N+1 here", tag or "fix") end
      session.add(range)
      return s, bufnr
    end

    it("persists the anchor, the tag and the snippet", function()
      local s, bufnr = seed({ 6, 8 })
      local c = s.store:comments()[1]
      assert.equals("award.py", c.file)
      assert.equals("new", c.side)
      assert.equals("fix", c.tag)
      assert.equals("human", c.author)
      assert.equals("open", c.status)
      assert.equals(6, c.line_start)
      assert.equals(8, c.line_end)
      assert.equals(3, #vim.split(c.snippet, "\n"))
      assert.is_true(c.snippet:find("fetch(award.id)", 1, true) ~= nil)
      assert.is_true(s.store:exists())
      assert.is_nil(c.rev, "a live new-side comment should carry no rev")
      assert.is_not_nil(bufnr)
    end)

    it("paints one sign extmark spanning the range", function()
      local _, bufnr = seed({ 6, 8 })
      local marks = vim.api.nvim_buf_get_extmarks(bufnr, render.ns, 0, -1, { details = true })
      assert.equals(1, #marks)
      assert.equals(5, marks[1][2], "extmark should start on row 6 (0-indexed 5)")
      assert.equals(7, marks[1][4].end_row)
      assert.is_not_nil(marks[1][4].sign_text)
    end)

    it("defaults to the cursor line when given no range", function()
      local v = open_diff(root)
      local bufnr = v.cur_entry.layout.b.file.bufnr
      vim.api.nvim_set_current_buf(bufnr)
      local win = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_buf(win, bufnr)
      vim.api.nvim_win_set_cursor(win, { 4, 0 })
      local s = session.attach()
      ui.compose = function(_, cb) cb("single", "nit") end
      session.add(nil)
      local c = s.store:comments()[1]
      assert.equals(4, c.line_start)
      assert.equals(4, c.line_end)
    end)

    it("publishes the session so an agent in this worktree can find it", function()
      local s = seed({ 6, 8 })
      local entry
      for _, e in ipairs(registry.read().sessions) do
        if e.repo_root == s.root then entry = e end
      end
      assert.is_not_nil(entry, "no registry entry for " .. s.root)
      assert.equals("main", entry.branch)
      assert.equals(1, entry.open)
      assert.equals(s.store.path, entry.store)
      assert.is_true(entry.live)
    end)

    it("drops the registry entry on detach", function()
      local s = seed({ 6, 8 })
      session.detach(s.root)
      for _, e in ipairs(registry.read().sessions) do
        assert.not_equals(s.root, e.repo_root)
      end
    end)
  end)

  describe("the agent round trip", function()
    local s, bufnr, c

    local function agent_writes(mutate)
      vim.wait(400) -- let the self-write suppression window lapse
      local disk = vim.json.decode(util.read(s.store.path))
      mutate(disk)
      write(s.store.path, util.encode_pretty(disk))
    end

    before_each(function()
      local v = open_diff(root)
      bufnr = v.cur_entry.layout.b.file.bufnr
      vim.api.nvim_set_current_buf(bufnr)
      s = session.attach()
      session.check_live(s)
      ui.compose = function(_, cb) cb("N+1 here", "fix") end
      session.add({ 6, 8 })
      c = s.store:comments()[1]
    end)

    it("picks up a resolve and a reply written from outside nvim", function()
      agent_writes(function(d)
        d.comments[1].status = "resolved"
        d.comments[1].replies = { { author = "claude", body = "batched it" } }
      end)
      local got = vim.wait(8000, function()
        local a = s.store:get(c.id)
        return a and a.status == "resolved"
      end, 100)
      assert.is_true(got, "resolve never arrived")
      assert.equals("batched it", s.store:get(c.id).replies[1].body)
    end)

    it("ingests a comment the agent originated", function()
      agent_writes(function(d)
        table.insert(d.comments, {
          id = "c-agent", file = "award.py", side = "new", line_start = 1, line_end = 1,
          tag = "q", author = "claude", status = "open",
          body = "tenant scoped?", snippet = "import os", replies = {},
        })
      end)
      local got = vim.wait(8000, function() return s.store:get("c-agent") ~= nil end, 100)
      assert.is_true(got, "agent comment never arrived")
      assert.equals("claude", s.store:get("c-agent").author)
    end)

    it("re-anchors when the agent rewrites the file above the comment", function()
      write(root .. "/award.py", "# one\n# two\n# three\n# four\n# five\n" .. util.read(root .. "/award.py"))
      agent_writes(function(d) d.comments[1].status = "open" end)
      local got = vim.wait(10000, function()
        local a = s.store:get(c.id)
        return a and a.line_start == 11
      end, 150)
      local a = s.store:get(c.id)
      assert.is_true(got, ("expected 11-13, got %s-%s"):format(a.line_start, a.line_end))
      assert.equals(13, a.line_end)
    end)

    it("orphans instead of mis-pointing when the code is deleted", function()
      local kept = {}
      for i, l in ipairs(vim.split(util.read(root .. "/award.py"), "\n", { plain = true })) do
        if i < 6 or i > 8 then kept[#kept + 1] = l end
      end
      write(root .. "/award.py", table.concat(kept, "\n"))
      agent_writes(function(d) d.comments[1].status = "open" end)
      local got = vim.wait(10000, function()
        local a = s.store:get(c.id)
        return a and a.status == "orphaned"
      end, 150)
      assert.is_true(got, "expected orphaned, got " .. tostring(s.store:get(c.id).status))
    end)
  end)

  describe("the old side", function()
    local function abbrev(rev)
      return (sh(root, "git rev-parse --short=11 " .. rev).stdout:gsub("%s+$", ""))
    end

    local function comment_on(v, side, range, body)
      local bufnr = v.cur_entry.layout[side].file.bufnr
      vim.api.nvim_set_current_buf(bufnr)
      ui.compose = function(_, cb) cb(body or "why was this removed?", "q") end
      session.add(range)
      return bufnr
    end

    local function marks(bufnr)
      return vim.api.nvim_buf_get_extmarks(bufnr, render.ns, 0, -1, {})
    end

    it("attaches the review keymaps to both diff buffers", function()
      require("review").setup()
      local v = open_diff(root, "HEAD~1..HEAD")
      local ok = vim.wait(5000, function()
        return vim.b[v.cur_entry.layout.a.file.bufnr].review_keys == true
          and vim.b[v.cur_entry.layout.b.file.bufnr].review_keys == true
      end, 100)
      assert.is_true(ok, "keymaps missing on one side of the diff")
      local lhs = vim.api.nvim_buf_call(v.cur_entry.layout.a.file.bufnr, function()
        return vim.fn.maparg(vim.g.mapleader and (vim.g.mapleader .. "rc") or "\\rc", "n")
      end)
      assert.is_true(lhs ~= "", "<leader>rc is not mapped on the old side")
    end)

    it("anchors an old-side comment to the base commit and paints only that side", function()
      local v = open_diff(root, "HEAD~1..HEAD")
      local s = session.attach()
      local a = comment_on(v, "a", { 4, 5 })
      local c = s.store:comments()[1]
      assert.equals("old", c.side)
      assert.equals(abbrev("HEAD~1"), c.rev)
      assert.equals(4, c.line_start)
      assert.equals(5, c.line_end)
      assert.is_true(c.snippet:find("def total", 1, true) ~= nil)
      assert.is_nil(c.old_file, "an unrenamed file needs no old_file")
      assert.equals(1, #marks(a))
      local b = v.cur_entry.layout.b.file.bufnr
      session.paint_buf(s, b)
      assert.equals(0, #marks(b))
    end)

    it("keeps a comment from another commit range out of this tab", function()
      local v = open_diff(root, "HEAD~1..HEAD")
      local s = session.attach()
      local b = comment_on(v, "b", { 6, 6 }, "new side here")
      s.store:mutate(function(d) d.comments[1].rev = "0000000000a" end)
      session.paint_buf(s, b)
      assert.equals(0, #marks(b))
    end)

    it("records where a renamed file's code used to live", function()
      sh(root, "git checkout -q -- . && git mv award.py awards.py && "
        .. "git -c user.email=t@t -c user.name=t commit -qm rename")
      local v = open_diff(root, "HEAD~1..HEAD")
      local s = session.attach()
      comment_on(v, "a", { 4, 4 })
      local c = s.store:comments()[1]
      assert.equals("awards.py", c.file)
      assert.equals("award.py", c.old_file)
      assert.equals("old", c.side)
    end)
  end)

  describe("export", function()
    it("copies the open comments and the store pointer to the + register", function()
      local v = open_diff(root)
      vim.api.nvim_set_current_buf(v.cur_entry.layout.b.file.bufnr)
      local s = session.attach()
      ui.compose = function(_, cb) cb("N+1 here", "fix") end
      session.add({ 6, 8 })
      vim.fn.setreg("+", "")
      session.export()
      local reg = vim.fn.getreg("+")
      assert.is_true(reg:find("N+1 here", 1, true) ~= nil, "clipboard: " .. reg)
      assert.is_true(reg:find(vim.fs.basename(s.store.path), 1, true) ~= nil)
    end)
  end)
end)
