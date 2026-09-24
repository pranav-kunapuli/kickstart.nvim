local Store = require("review.store")
local util = require("review.util")

local function tmproot()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

describe("store", function()
  it("does not create a file until something is written", function()
    local s = Store.new(tmproot(), "main", "main")
    assert.is_false(s:exists())
    assert.are.same({}, s:comments())
  end)

  it("slugifies a branch name with slashes", function()
    local s = Store.new(tmproot(), "feature/awa-123/thing", "main")
    assert.equals("feature__awa-123__thing.json", vim.fs.basename(s.path))
  end)

  it("fills in id, author, status and replies on add", function()
    local s = Store.new(tmproot(), "main", "main")
    local c = s:add({ file = "a.py", line_start = 1, line_end = 1, tag = "fix", body = "b" })
    assert.is_string(c.id)
    assert.equals("human", c.author)
    assert.equals("open", c.status)
    assert.are.same({}, c.replies)
    assert.is_string(c.created_at)
    assert.is_true(s:exists())
  end)

  it("counts open, resolved and orphaned separately", function()
    local s = Store.new(tmproot(), "main", "main")
    s:add({ file = "a", body = "1" })
    s:add({ file = "a", body = "2", status = "resolved" })
    s:add({ file = "a", body = "3", status = "orphaned" })
    local open, resolved, orphaned = s:counts()
    assert.equals(1, open)
    assert.equals(1, resolved)
    assert.equals(1, orphaned)
  end)

  it("survives a corrupt store instead of throwing", function()
    local root = tmproot()
    local s = Store.new(root, "main", "main")
    util.write_atomic(s.path, "{ this is not json")
    assert.is_nil(s:read())
  end)

  -- The whole lock-free design rests on this: every write re-reads first, and
  -- the two sides own disjoint fields.
  describe("concurrent writes", function()
    it("keeps an agent's resolve when nvim adds a comment", function()
      local root = tmproot()
      local s = Store.new(root, "main", "main")
      local c = s:add({ file = "a.py", body = "human comment" })

      -- agent, from another process, resolves and replies
      local disk = vim.json.decode(util.read(s.path))
      disk.comments[1].status = "resolved"
      disk.comments[1].replies = { { author = "claude", body = "done" } }
      util.write_atomic(s.path, util.encode_pretty(disk))

      -- nvim, unaware, adds a second comment
      s:add({ file = "b.py", body = "second" })

      local fresh = vim.json.decode(util.read(s.path))
      assert.equals(2, #fresh.comments)
      assert.equals("resolved", fresh.comments[1].status, "agent's resolve was clobbered")
      assert.equals("done", fresh.comments[1].replies[1].body)
      assert.equals("second", fresh.comments[2].body)
      assert.equals(c.id, fresh.comments[1].id)
    end)

    it("keeps an agent's new comment when nvim resolves an old one", function()
      local root = tmproot()
      local s = Store.new(root, "main", "main")
      local c = s:add({ file = "a.py", body = "human comment" })

      local disk = vim.json.decode(util.read(s.path))
      table.insert(disk.comments, {
        id = "c-agent", file = "b.py", author = "claude", status = "open",
        tag = "q", body = "from the agent", replies = {},
      })
      util.write_atomic(s.path, util.encode_pretty(disk))

      s:update(c.id, function(x) x.status = "resolved" end)

      local fresh = vim.json.decode(util.read(s.path))
      assert.equals(2, #fresh.comments)
      assert.equals("resolved", fresh.comments[1].status)
      assert.equals("from the agent", fresh.comments[2].body, "agent's comment was lost")
    end)

    it("keeps an agent's reply when nvim deletes a different comment", function()
      local root = tmproot()
      local s = Store.new(root, "main", "main")
      local a = s:add({ file = "a.py", body = "one" })
      s:add({ file = "b.py", body = "two" })

      local disk = vim.json.decode(util.read(s.path))
      disk.comments[2].replies = { { author = "claude", body = "noted" } }
      util.write_atomic(s.path, util.encode_pretty(disk))

      s:delete(a.id)

      local fresh = vim.json.decode(util.read(s.path))
      assert.equals(1, #fresh.comments)
      assert.equals("two", fresh.comments[1].body)
      assert.equals("noted", fresh.comments[1].replies[1].body)
    end)
  end)

  describe("watch", function()
    it("fires on an external write and not on our own", function()
      local root = tmproot()
      local s = Store.new(root, "main", "main")
      s:add({ file = "a.py", body = "seed" })

      local fired = 0
      s:watch(function() fired = fired + 1 end)

      -- our own write must be suppressed
      s:add({ file = "b.py", body = "ours" })
      vim.wait(400)
      assert.equals(0, fired, "self-write leaked through the watcher")

      vim.wait(300) -- let the suppression window lapse
      local disk = vim.json.decode(util.read(s.path))
      disk.comments[1].status = "resolved"
      util.write_atomic(s.path, util.encode_pretty(disk))

      local got = vim.wait(3000, function() return fired > 0 end, 50)
      s:stop()
      assert.is_true(got, "watcher never fired on an external write")
    end)
  end)
end)
