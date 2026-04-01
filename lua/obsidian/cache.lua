local Path = require "obsidian.path"

---@class obsidian.NoteCache.Entry
---@field note obsidian.Note
---@field code_blocks {[1]: integer, [2]: integer}[]
---@field mtime integer

---@class obsidian.NoteCache
---@field _entries table<string, obsidian.NoteCache.Entry>
local NoteCache = {}
NoteCache.__index = NoteCache

---Create a new NoteCache instance.
---@return obsidian.NoteCache
NoteCache.new = function()
  local self = setmetatable({}, NoteCache)
  self._entries = {}
  return self
end

---Get a cached note entry, or parse and cache the note if stale/missing.
---Returns nil if the file does not exist.
---
---@param path_str string Resolved absolute path to the note file.
---@param opts obsidian.note.LoadOpts|?
---
---@return obsidian.NoteCache.Entry|?
NoteCache.get = function(self, path_str, opts)
  path_str = tostring(Path.new(path_str):resolve())

  local stat = vim.uv.fs_stat(path_str)
  if not stat then
    return nil
  end

  local mtime = stat.mtime.sec

  local entry = self._entries[path_str]
  if entry and entry.mtime == mtime then
    return entry
  end

  local Note = require "obsidian.note"
  local search = require "obsidian.search"

  opts = opts or {}

  local note = Note.from_file(path_str, opts)
  local code_blocks = search.find_code_blocks(note.contents)

  entry = {
    note = note,
    code_blocks = code_blocks,
    mtime = mtime,
  }
  self._entries[path_str] = entry

  return entry
end

---Invalidate (remove) a single cache entry.
---
---@param path_str string Resolved absolute path to the note file.
NoteCache.invalidate = function(self, path_str)
  path_str = tostring(Path.new(path_str):resolve())
  self._entries[path_str] = nil
end

---Clear all cache entries.
NoteCache.clear = function(self)
  self._entries = {}
end

---Return the number of cached entries.
---
---@return integer
NoteCache.size = function(self)
  return vim.tbl_count(self._entries)
end

return NoteCache
