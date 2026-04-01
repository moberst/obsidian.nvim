local log = require "obsidian.log"

---@param _data obsidian.CommandArgs
return function(_data)
  if not Obsidian.note_cache then
    log.warn "Note cache not initialized"
    return
  end

  local old_size = Obsidian.note_cache:size()
  Obsidian.note_cache:clear()
  log.info("Note cache cleared (%d entries removed)", old_size)
end
