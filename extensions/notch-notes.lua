local ENTRY_KIND = "trobrock.notch-notes"
local STATUS_KEY = "notch-notes"
local PANEL_KEY = "notch-notes"
local MAX_LABEL_RUNES = 76
local MAX_PANEL_NOTES = 12

local notes = {}
local next_id = 1
local tui_mode = false

local function trim(value)
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function collapse_whitespace(value)
  return trim(value:gsub("%s+", " "))
end

local function truncate(value, max_runes)
  local runes = {}
  for codepoint in value:gmatch("[\0-\127\194-\244][\128-\191]*") do
    runes[#runes + 1] = codepoint
    if #runes > max_runes then
      break
    end
  end
  if #runes <= max_runes then
    return value
  end
  runes[max_runes] = "…"
  for index = max_runes + 1, #runes do
    runes[index] = nil
  end
  return table.concat(runes)
end

local function note_label(note)
  local label = collapse_whitespace(note.text)
  if label == "" then
    label = "(blank note)"
  end
  return truncate(label, MAX_LABEL_RUNES)
end

local function plural_notes(count)
  if count == 1 then
    return "1 note"
  end
  return tostring(count) .. " notes"
end

local function update_next_id(id)
  local numeric = tonumber(id:match("^(%d+)$"))
  if numeric and numeric >= next_id then
    next_id = numeric + 1
  end
end

local function reconstruct()
  local active = {}
  local order = {}
  next_id = 1

  local ok, entries = pcall(notch.session.entries, ENTRY_KIND)
  if not ok then
    notes = {}
    return false
  end
  for _, entry in ipairs(entries) do
    if type(entry) == "table" and entry.action == "add" and type(entry.note) == "table" then
      local note = entry.note
      if type(note.id) == "string" and type(note.text) == "string" and type(note.created_at) == "string" then
        if active[note.id] == nil then
          order[#order + 1] = note.id
        end
        active[note.id] = note
        update_next_id(note.id)
      end
    elseif type(entry) == "table" and entry.action == "consume" and type(entry.id) == "string" then
      active[entry.id] = nil
    elseif type(entry) == "table" and entry.action == "clear" and type(entry.ids) == "table" then
      for _, id in ipairs(entry.ids) do
        if type(id) == "string" then
          active[id] = nil
        end
      end
    end
  end

  notes = {}
  for _, id in ipairs(order) do
    if active[id] ~= nil then
      notes[#notes + 1] = active[id]
    end
  end
  return true
end

local function sync_ui()
  if not tui_mode then
    return
  end
  if #notes == 0 then
    notch.ui.set_status(STATUS_KEY, "")
    notch.ui.set_panel(PANEL_KEY, "", {})
    return
  end

  notch.ui.set_status(STATUS_KEY, "notes " .. tostring(#notes))
  local lines = {}
  local visible = math.min(#notes, MAX_PANEL_NOTES)
  for index = 1, visible do
    lines[#lines + 1] = tostring(index) .. ". " .. note_label(notes[index])
  end
  if #notes > visible then
    lines[#lines + 1] = "… " .. tostring(#notes - visible) .. " more"
  end
  lines[#lines + 1] = "/notes to use one"
  notch.ui.set_panel(PANEL_KEY, "📝 " .. plural_notes(#notes) .. " pending", lines)
end

local function load_state()
  if reconstruct() then
    sync_ui()
  else
    notch.ui.set_status(STATUS_KEY, "")
    notch.ui.set_panel(PANEL_KEY, "", {})
    notch.ui.notify("Session notes are unavailable because session persistence is disabled.", "warning")
  end
end

local function append_to_editor(existing, addition)
  if existing == "" then
    return addition
  end
  if existing:sub(-1) == "\n" then
    return existing .. addition
  end
  return existing .. "\n" .. addition
end

local function find_note(id)
  for index, note in ipairs(notes) do
    if note.id == id then
      return index, note
    end
  end
  return nil, nil
end

local function consume(note)
  notch.session.append(ENTRY_KIND, {
    action = "consume",
    id = note.id,
    consumed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  })
  local index = find_note(note.id)
  if index ~= nil then
    table.remove(notes, index)
  end
  sync_ui()
end

local function clear_notes()
  local ids = {}
  for _, note in ipairs(notes) do
    ids[#ids + 1] = note.id
  end
  notch.session.append(ENTRY_KIND, {
    action = "clear",
    ids = ids,
    cleared_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  })
  notes = {}
  sync_ui()
end

local function select_note()
  local options = {}
  local by_option = {}
  for index, note in ipairs(notes) do
    local option = tostring(index) .. ". " .. note_label(note) .. " — " .. note.created_at
    options[#options + 1] = option
    by_option[option] = note
  end
  options[#options + 1] = "Cancel"
  local selected = notch.ui.select("Session notes", options)
  if selected == "Cancel" then
    return nil
  end
  return by_option[selected]
end

notch.register_command({
  name = "note",
  description = "Save text as a note in the current session",
  allow_while_streaming = true,
  execute = function(args)
    local text = trim(args)
    if text == "" then
      return "Usage: /note <note text>"
    end
    if not reconstruct() then
      return "/note requires session persistence."
    end

    local id = tostring(next_id)
    next_id = next_id + 1
    local note = {
      id = id,
      text = text,
      created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    notch.session.append(ENTRY_KIND, {action = "add", note = note})
    notes[#notes + 1] = note
    sync_ui()
    notch.ui.notify("Saved note (" .. plural_notes(#notes) .. " pending). Use /notes to pick it later.", "info")
  end,
})

notch.register_command({
  name = "notes",
  description = "Pick a saved session note and move it to the prompt editor",
  execute = function(args)
    if not tui_mode then
      return "/notes requires the fullscreen TUI."
    end
    local subcommand = trim(args)
    reconstruct()
    sync_ui()

    if subcommand == "clear" then
      if #notes == 0 then
        return "No stored session notes."
      end
      local answer = notch.ui.select("Clear " .. plural_notes(#notes) .. "?", {"Clear notes", "Cancel"})
      if answer == "Clear notes" then
        clear_notes()
        notch.ui.notify("Session notes cleared", "info")
      end
      return
    end

    if subcommand ~= "" then
      return "Usage: /notes or /notes clear"
    end
    if #notes == 0 then
      return "No stored session notes."
    end

    local note = select_note()
    if note == nil then
      return
    end

    local current = notch.ui.editor_text()
    local next_text = note.text
    if trim(current) ~= "" then
      local insertion = notch.ui.select("Editor already has text. Insert selected note how?", {
        "Replace editor text",
        "Append to editor text",
        "Cancel",
      })
      if insertion == "Cancel" then
        return
      elseif insertion == "Append to editor text" then
        next_text = append_to_editor(current, note.text)
      end
    end

    notch.ui.set_editor_text(next_text)
    consume(note)
    notch.ui.notify("Note moved to prompt editor", "info")
  end,
})

notch.on("session_start", function(event)
  tui_mode = event.mode == "tui"
  if not tui_mode then
    reconstruct()
    return
  end
  load_state()
end)

notch.on("session_change", function()
  if tui_mode then
    load_state()
  else
    reconstruct()
  end
end)

notch.on("session_shutdown", function()
  notes = {}
  if tui_mode then
    notch.ui.set_status(STATUS_KEY, "")
    notch.ui.set_panel(PANEL_KEY, "", {})
  end
  tui_mode = false
end)
