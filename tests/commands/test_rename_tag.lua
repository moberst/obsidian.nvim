local h = dofile "tests/helpers.lua"
local child

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T, child = h.child_vault()

--- Helper to write a file and run rename_tag in the child process.
---@param files table<string, string> Map of relative path to file content.
---@param old_tag string
---@param new_tag string
---@return table<string, string[]> Map of relative path to resulting lines.
local function run_rename(files, old_tag, new_tag)
  local root = child.lua_get [[tostring(Obsidian.dir)]]

  -- Write files.
  for rel_path, content in pairs(files) do
    local filepath = vim.fs.joinpath(root, rel_path)
    vim.fn.writefile(vim.split(content, "\n"), filepath)
  end

  -- Run the rename command (bypass confirmation by mocking api.confirm).
  child.lua(string.format(
    [[
local api = require "obsidian.api"
api.confirm = function() return "Yes" end
local cmd = require "obsidian.commands.rename_tag"
cmd({ fargs = { %q, %q } })
  ]],
    old_tag,
    new_tag
  ))

  -- Wait for async search + file writes to complete.
  vim.uv.sleep(500)

  -- Read back the files.
  local results = {}
  for rel_path, _ in pairs(files) do
    local filepath = vim.fs.joinpath(root, rel_path)
    results[rel_path] = vim.fn.readfile(filepath)
  end
  return results
end

T["renames inline tags"] = function()
  local results = run_rename({
    ["note1.md"] = "Some text #foo and more #bar here",
  }, "foo", "baz")

  eq(results["note1.md"][1], "Some text #baz and more #bar here")
end

T["renames frontmatter tags"] = function()
  local results = run_rename({
    ["note2.md"] = table.concat({
      "---",
      "tags:",
      "  - foo",
      "  - bar",
      "---",
      "",
      "Body text here",
    }, "\n"),
  }, "foo", "baz")

  -- The frontmatter should contain baz instead of foo.
  local content = table.concat(results["note2.md"], "\n")
  local has_baz = content:find "baz" ~= nil
  local has_foo = content:find "foo" ~= nil
  eq(has_baz, true)
  eq(has_foo, false)
end

T["renames both inline and frontmatter tags"] = function()
  local results = run_rename({
    ["note3.md"] = table.concat({
      "---",
      "tags:",
      "  - foo",
      "---",
      "",
      "Some #foo text",
    }, "\n"),
  }, "foo", "baz")

  local content = table.concat(results["note3.md"], "\n")
  -- Should have baz in both frontmatter and body.
  eq(content:find "#baz" ~= nil, true)
  -- Should not have foo anywhere.
  eq(content:find "foo" == nil, true)
end

T["renames nested tags preserving hierarchy"] = function()
  local results = run_rename({
    ["note4.md"] = "#foo #foo/bar #foo/baz/qux #foobar",
  }, "foo", "quux")

  local line = results["note4.md"][1]
  -- #foo -> #quux, #foo/bar -> #quux/bar, #foo/baz/qux -> #quux/baz/qux
  eq(line:find "#quux " ~= nil, true)
  eq(line:find "#quux/bar" ~= nil, true)
  eq(line:find "#quux/baz/qux" ~= nil, true)
  -- #foobar should be unchanged (not a prefix match).
  eq(line:find "#foobar" ~= nil, true)
end

T["does not rename tags in code blocks"] = function()
  local results = run_rename({
    ["note5.md"] = table.concat({
      "#foo outside",
      "",
      "```",
      "#foo inside code",
      "```",
      "",
      "#foo after",
    }, "\n"),
  }, "foo", "baz")

  eq(results["note5.md"][1], "#baz outside")
  eq(results["note5.md"][4], "#foo inside code") -- unchanged
  eq(results["note5.md"][7], "#baz after")
end

T["renames across multiple files"] = function()
  local results = run_rename({
    ["a.md"] = "#foo in file a",
    ["b.md"] = "#foo in file b",
  }, "foo", "baz")

  eq(results["a.md"][1], "#baz in file a")
  eq(results["b.md"][1], "#baz in file b")
end

T["does not rename partial matches"] = function()
  local results = run_rename({
    ["note6.md"] = "#foobar #barfoo #foo",
  }, "foo", "baz")

  local line = results["note6.md"][1]
  eq(line:find "#foobar" ~= nil, true) -- unchanged
  eq(line:find "#barfoo" ~= nil, true) -- unchanged
  eq(line:find "#baz" ~= nil, true) -- renamed
end

return T
