local log = require "obsidian.log"
local api = require "obsidian.api"
local search = require "obsidian.search"
local Path = require "obsidian.path"
local Note = require "obsidian.note"

---@param data obsidian.CommandArgs
return function(data)
  local fargs = data.fargs or {}
  local tag = fargs[1] or ""
  local label = fargs[2]
  local offset = tonumber(fargs[3]) or 0
  -- Strip leading '#' if provided
  tag = tag:gsub("^#", "")

  if tag == "" then
    log.err "A tag argument is required"
    return
  end

  local dir = api.resolve_workspace_dir()

  search.find_tags_async({ tag }, function(tag_locations)
    -- Filter to exact tag matches (same logic as tags.lua gather_tag_picker_list)
    ---@type table<string, obsidian.TagLocation>
    local seen = {}
    for _, tag_loc in ipairs(tag_locations) do
      if tag_loc.tag:lower() == tag:lower() or vim.startswith(tag_loc.tag:lower(), tag:lower() .. "/") then
        local path_str = tostring(tag_loc.path)
        if not seen[path_str] then
          seen[path_str] = tag_loc
        end
      end
    end

    local unique_locs = vim.tbl_values(seen)

    if vim.tbl_isempty(unique_locs) then
      log.warn("No notes found with tag '#%s'", tag)
      return
    end

    -- Sort by file modification time descending
    table.sort(unique_locs, function(a, b)
      local stat_a = Path.new(tostring(a.path)):stat()
      local stat_b = Path.new(tostring(b.path)):stat()
      local mtime_a = stat_a and stat_a.mtime.sec or 0
      local mtime_b = stat_b and stat_b.mtime.sec or 0
      return mtime_a > mtime_b
    end)

    if offset + 1 > #unique_locs then
      log.warn("Offset %d is out of range (only %d notes found with tag '#%s')", offset, #unique_locs, tag)
      return
    end

    local selected = unique_locs[offset + 1]
    local note = Note.from_file(tostring(selected.path))
    local link = note:format_link(label and { label = label } or nil)

    vim.schedule(function()
      vim.api.nvim_put({ link }, "", false, true)
      require("obsidian.ui").update(0)
    end)
  end, { dir = dir })
end
