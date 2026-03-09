local log = require "obsidian.log"
local util = require "obsidian.util"
local api = require "obsidian.api"
local search = require "obsidian.search"
local Note = require "obsidian.note"

--- Check if a tag matches old_tag exactly or is a nested child (e.g. old_tag/...).
---@param tag string
---@param old_tag string
---@return boolean
local function tag_matches(tag, old_tag)
  local tag_lower = tag:lower()
  local old_lower = old_tag:lower()
  return tag_lower == old_lower or vim.startswith(tag_lower, old_lower .. "/")
end

--- Compute the renamed tag: replace the old_tag prefix with new_tag.
---@param tag string
---@param old_tag string
---@param new_tag string
---@return string
local function rename_tag(tag, old_tag, new_tag)
  -- Preserve the original casing of the suffix for nested tags.
  if tag:lower() == old_tag:lower() then
    return new_tag
  end
  -- Nested: replace the prefix.
  return new_tag .. tag:sub(#old_tag + 1)
end

--- Replace inline tags in a list of content lines, skipping code blocks.
--- Returns the modified lines and the number of replacements made.
---@param lines string[]
---@param old_tag string
---@param new_tag string
---@param code_blocks { [1]: integer, [2]: integer }[]
---@param frontmatter_end_line integer|?
---@return string[], integer
local function replace_inline_tags(lines, old_tag, new_tag, code_blocks, frontmatter_end_line)
  local count = 0

  ---@param lnum integer 1-indexed line number
  ---@return boolean
  local function in_code_block(lnum)
    for _, block in ipairs(code_blocks) do
      if block[1] <= lnum and lnum <= block[2] then
        return true
      end
    end
    return false
  end

  ---@param lnum integer
  ---@return boolean
  local function in_frontmatter(lnum)
    return frontmatter_end_line ~= nil and lnum < frontmatter_end_line
  end

  for i, line in ipairs(lines) do
    if not in_code_block(i) and not in_frontmatter(i) then
      local matches = util.parse_tags(line)
      if #matches > 0 then
        -- Process right-to-left to preserve byte positions.
        for j = #matches, 1, -1 do
          local m_start, m_end, _ = unpack(matches[j])
          local tag_body = line:sub(m_start + 1, m_end) -- skip the '#'
          if tag_matches(tag_body, old_tag) then
            local replacement = rename_tag(tag_body, old_tag, new_tag)
            -- Replace the tag body (after '#').
            line = line:sub(1, m_start) .. replacement .. line:sub(m_end + 1)
            count = count + 1
          end
        end
        lines[i] = line
      end
    end
  end

  return lines, count
end

--- Replace tags in a note's frontmatter tags array.
---@param tags string[]
---@param old_tag string
---@param new_tag string
---@return string[], integer
local function replace_frontmatter_tags(tags, old_tag, new_tag)
  local count = 0
  for i, tag in ipairs(tags) do
    if tag_matches(tag, old_tag) then
      tags[i] = rename_tag(tag, old_tag, new_tag)
      count = count + 1
    end
  end
  return tags, count
end

---@param data obsidian.CommandArgs
return function(data)
  local args = data.fargs or {}

  local old_tag, new_tag

  if #args >= 2 then
    old_tag = args[1]
    new_tag = args[2]
  elseif #args == 1 then
    old_tag = args[1]
  else
    old_tag = api.cursor_tag()
  end

  -- Strip leading '#' if present.
  if old_tag then
    old_tag = old_tag:gsub("^#", "")
  end

  if not old_tag or old_tag == "" then
    log.err "No tag specified and no tag found under cursor"
    return
  end

  if not new_tag then
    new_tag = api.input("Rename #" .. old_tag .. " to")
    if not new_tag then
      log.warn "Aborted"
      return
    end
  end

  -- Strip leading '#' if present.
  new_tag = new_tag:gsub("^#", "")

  if new_tag == "" then
    log.err "New tag name cannot be empty"
    return
  end

  if old_tag:lower() == new_tag:lower() then
    log.warn "Old and new tag names are the same"
    return
  end

  -- Validate new tag matches allowed pattern.
  if not string.match(new_tag, "^" .. search.Patterns.TagCharsRequired .. "$") then
    log.err("Invalid tag name: '%s'", new_tag)
    return
  end

  local dir = api.resolve_workspace_dir()

  search.find_tags_async(old_tag, function(tag_locations)
    -- Filter to exact matches and nested children.
    ---@type obsidian.TagLocation[]
    local matches = {}
    for _, tag_loc in ipairs(tag_locations) do
      if tag_matches(tag_loc.tag, old_tag) then
        matches[#matches + 1] = tag_loc
      end
    end

    if #matches == 0 then
      vim.schedule(function()
        log.info("No occurrences of #%s found", old_tag)
      end)
      return
    end

    -- Count unique files.
    local file_set = {}
    for _, m in ipairs(matches) do
      file_set[tostring(m.path)] = true
    end
    local file_count = vim.tbl_count(file_set)

    vim.schedule(function()
      local choice = api.confirm(
        string.format(
          "Rename #%s -> #%s: %d occurrence(s) across %d file(s). Continue?",
          old_tag,
          new_tag,
          #matches,
          file_count
        )
      )
      if choice ~= "Yes" then
        log.warn "Aborted"
        return
      end

      -- Group matches by file path.
      ---@type table<string, obsidian.TagLocation[]>
      local by_file = {}
      for _, m in ipairs(matches) do
        local key = tostring(m.path)
        if not by_file[key] then
          by_file[key] = {}
        end
        by_file[key][#by_file[key] + 1] = m
      end

      local total_replaced = 0

      for path_str, file_matches in pairs(by_file) do
        local has_frontmatter_matches = false
        local has_inline_matches = false
        local note = file_matches[1].note

        for _, m in ipairs(file_matches) do
          if note.has_frontmatter and note.frontmatter_end_line and m.line < note.frontmatter_end_line then
            has_frontmatter_matches = true
          else
            has_inline_matches = true
          end
        end

        -- Reload the note with contents for inline replacement.
        if has_inline_matches then
          note = Note.from_file(path_str, {
            load_contents = true,
            max_lines = Obsidian.opts.search.max_lines,
          })
          local code_blocks = search.find_code_blocks(note.contents)
          local new_contents, inline_count =
            replace_inline_tags(note.contents, old_tag, new_tag, code_blocks, note.frontmatter_end_line)
          total_replaced = total_replaced + inline_count

          -- Save with updated content.
          note:save {
            insert_frontmatter = has_frontmatter_matches and note:should_save_frontmatter(),
            update_content = function()
              -- Return content lines after frontmatter.
              local body = {}
              local start_line = note.frontmatter_end_line and note.frontmatter_end_line or 0
              for i = start_line + 1, #new_contents do
                body[#body + 1] = new_contents[i]
              end
              return body
            end,
          }
        end

        if has_frontmatter_matches then
          -- Reload note to get fresh state (especially after content save above).
          if has_inline_matches then
            note = Note.from_file(path_str)
          end
          local _, fm_count = replace_frontmatter_tags(note.tags, old_tag, new_tag)
          total_replaced = total_replaced + fm_count

          if note:should_save_frontmatter() then
            note:save { insert_frontmatter = true }
          end
        end
      end

      log.info("Renamed %d occurrence(s) of #%s -> #%s across %d file(s)", total_replaced, old_tag, new_tag, file_count)
    end)
  end, { dir = dir })
end
