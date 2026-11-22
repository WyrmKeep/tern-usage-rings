if tern.chrome == nil or tern.chrome.widget == nil or tern.css == nil then
	error("Usage Rings needs a Tern that has the widget bar API, such as 0.9.26")
end

local model = require("./lib/model")
local sheet = require("./lib/sheet")

local POLL_MS = 5 * 60 * 1000
local OMP_TIMEOUT_MS = 90 * 1000
local TICK_MS = 60 * 1000
local WIDGET_PREFIX = "usage-rings/"
local FALLBACK_ICON = "chart"

local fixture_path = tern.getenv("USAGE_RINGS_FIXTURE")
local history_fixture_path = tern.getenv("USAGE_RINGS_HISTORY_FIXTURE")
local uses_fixture = fixture_path ~= nil and fixture_path ~= ""

local shown = {
	data = nil,
	history = nil,
	fetched_at = nil,
	error = nil,
	loading = true,
}
local states = {}
local views = {}
local icons = {}
local placed_badges = {}
local installed_css = nil

local function badge_of_widget(entry)
	local widget = type(entry) == "table" and entry.id or nil
	if type(widget) == "string" and string.sub(widget, 1, #WIDGET_PREFIX) == WIDGET_PREFIX then
		return string.sub(widget, #WIDGET_PREFIX + 1)
	end
	return nil
end

local function placed_widgets(cx)
	local widgets = cx.settings:get("widgets")
	return type(widgets) == "table" and widgets or {}
end

local function note_placed_badges(cx)
	if cx == nil then
		return
	end
	placed_badges = {}
	for _, entry in ipairs(placed_widgets(cx)) do
		local badge = badge_of_widget(entry)
		if badge ~= nil then
			table.insert(placed_badges, badge)
		end
	end
end

local function wall_clock_ms()
	return os.time() * 1000
end

local function model_clock_ms()
	if uses_fixture and shown.data ~= nil and type(shown.data.generatedAt) == "number" then
		return shown.data.generatedAt
	end
	return wall_clock_ms()
end

local function register_widget(state)
	local function spec(icon)
		return {
			name = state.name,
			description = state.name .. " usage across your accounts",
			icon = icon,
			styles = { "text" },
			render = function()
				return views[state.id]
			end,
		}
	end
	if pcall(tern.chrome.widget, state.id, spec(state.icon)) then
		icons[state.id] = state.icon
	else
		tern.chrome.widget(state.id, spec(FALLBACK_ICON))
		icons[state.id] = FALLBACK_ICON
	end
end

local function rebuild()
	states = model.build({
		data = shown.data,
		history = shown.history,
		now = model_clock_ms(),
		fetched_at = shown.fetched_at,
		loading = shown.loading,
		error = shown.error,
		placed = placed_badges,
	})
	local present = {}
	for _, state in ipairs(states) do
		present[state.id] = true
		views[state.id] = state.view
		if icons[state.id] == nil then
			register_widget(state)
		end
	end
	for id in pairs(icons) do
		if not present[id] then
			tern.chrome.widget(id, nil)
			icons[id] = nil
			views[id] = nil
		end
	end
	local css = sheet.render(states)
	if css ~= installed_css then
		tern.css("values", css)
		installed_css = css
	end
end

local function redraw(cx)
	note_placed_badges(cx)
	rebuild()
	tern.chrome.refresh()
end

local function stored(key)
	local ok, value = pcall(tern.kv.get, key)
	return ok and value or nil
end

local function store(key, value)
	local ok, err = pcall(tern.kv.set, key, value)
	if not ok then
		tern.log.warn("usage-rings: cannot write the store: " .. tostring(err))
	end
end

local function show(answer)
	shown.data = answer.data
	shown.history = answer.history
	shown.fetched_at = answer.at
	shown.error = nil
	shown.loading = false
end

local function omp_candidates()
	local candidates = { "omp" }
	local home = tern.getenv("HOME")
	if home ~= nil and home ~= "" then
		local data_home = tern.getenv("XDG_DATA_HOME")
		if data_home ~= nil and data_home ~= "" then
			table.insert(candidates, data_home .. "/tern/omp/bin/omp")
		end
		table.insert(candidates, home .. "/.local/share/tern/omp/bin/omp")
		table.insert(candidates, home .. "/Library/Application Support/Tern/omp/bin/omp")
	end
	local local_app_data = tern.getenv("LOCALAPPDATA")
	if local_app_data ~= nil and local_app_data ~= "" then
		table.insert(candidates, local_app_data .. "\\Tern\\omp\\bin\\omp.exe")
	end
	return candidates
end

local function decoded_json(output)
	local first_brace = string.find(output or "", "{", 1, true)
	if first_brace == nil then
		return nil
	end
	local ok, decoded = pcall(tern.json.decode, string.sub(output, first_brace))
	return ok and type(decoded) == "table" and decoded or nil
end

local function first_printed_line(output)
	local printable = string.gsub(string.gsub(output or "", "\27%[[%d;]*%a", ""), "[^\n\32-\126]", "")
	return string.match(printable, "([^%s][^\n]*)")
end

local function run_omp(args, done)
	local candidates = omp_candidates()
	local function try(index)
		local argv = { candidates[index] }
		for _, arg in ipairs(args) do
			table.insert(argv, arg)
		end
		local started, spawn_error = pcall(tern.process.run, argv, { timeout_ms = OMP_TIMEOUT_MS }, function(result)
			if result.timed_out then
				done(nil, "omp timed out")
			elseif result.status ~= 0 then
				done(nil, first_printed_line(result.stderr) or ("exit " .. tostring(result.status)))
			else
				local decoded = decoded_json(result.stdout)
				if decoded ~= nil then
					done(decoded, nil)
				else
					done(nil, "omp printed no JSON")
				end
			end
		end)
		if started then
			return
		elseif index < #candidates then
			try(index + 1)
		else
			tern.log.warn("usage-rings: cannot start omp: " .. tostring(spawn_error))
			done(nil, "omp not found")
		end
	end
	try(1)
end

local function badges_without_limits(data)
	local missing, any = {}, false
	for _, state in ipairs(model.build({ data = data, now = wall_clock_ms() })) do
		if not state.has_limits then
			missing[state.id] = true
			any = true
		end
	end
	return missing, any
end

local function history_for(history, data, missing)
	local badge_of_provider = model.badge_of_provider(data)
	local entries = tern.json.array()
	for _, entry in ipairs(history.entries or {}) do
		local badge = badge_of_provider(entry.provider)
		if badge ~= nil and missing[badge] then
			table.insert(entries, entry)
		end
	end
	return { entries = entries }
end

local poll

local function poll_in(ms)
	tern.timer(ms + math.random(0, 3000), poll)
end

local function finish_poll(data, history, err)
	store("reading", nil)
	if data ~= nil then
		local answer = { at = wall_clock_ms(), data = data, history = history }
		store("usage", answer)
		show(answer)
	else
		shown.error = err
		shown.loading = false
	end
	redraw()
	poll_in(POLL_MS)
end

function poll()
	local now = wall_clock_ms()
	local answer = stored("usage")
	if type(answer) == "table" and type(answer.at) == "number" and now >= answer.at and now - answer.at < POLL_MS then
		if answer.at ~= shown.fetched_at or shown.error ~= nil then
			show(answer)
			redraw()
		end
		poll_in(POLL_MS - (now - answer.at))
		return
	end
	local reading_since = stored("reading")
	if type(reading_since) == "number" and now >= reading_since and now - reading_since < OMP_TIMEOUT_MS then
		poll_in(5000)
		return
	end
	store("reading", now)
	run_omp({ "usage", "--json" }, function(data, err)
		if data == nil then
			finish_poll(nil, nil, err)
			return
		end
		local missing, any_missing = badges_without_limits(data)
		if not any_missing then
			finish_poll(data, nil, nil)
			return
		end
		store("reading", wall_clock_ms())
		run_omp({ "usage", "--history", "--json", "-d", "1" }, function(history)
			finish_poll(data, history ~= nil and history_for(history, data, missing) or nil, nil)
		end)
	end)
end

local function tick(cx)
	redraw(cx)
	tern.timer(TICK_MS, tick)
end

local function read_fixture(path)
	local ok, decoded = pcall(function()
		return tern.json.decode(tern.fs.read(path))
	end)
	if ok and type(decoded) == "table" then
		return decoded
	end
	tern.log.warn("usage-rings: cannot read fixture " .. tostring(path))
	return nil
end

local function toggle_badge(cx, badge)
	local kept, was_shown, last_badge_at = tern.json.array(), false, nil
	for _, entry in ipairs(placed_widgets(cx)) do
		local placed = badge_of_widget(entry)
		if placed == badge then
			was_shown = true
		else
			table.insert(kept, entry)
			if placed ~= nil then
				last_badge_at = #kept
			end
		end
	end
	if not was_shown then
		table.insert(kept, (last_badge_at or #kept) + 1, { id = WIDGET_PREFIX .. badge })
	end
	cx.settings:set("widgets", kept)
	redraw(cx)
end

local function choose_providers(cx)
	note_placed_badges(cx)
	local is_shown = {}
	for _, badge in ipairs(placed_badges) do
		is_shown[badge] = true
	end
	local items = {}
	for _, state in ipairs(states) do
		table.insert(items, {
			label = state.name,
			detail = state.summary,
			icon = icons[state.id],
			current = is_shown[state.id] == true,
			badge = state.id,
		})
	end
	cx:pick({ items = items, placeholder = "Show or hide a provider", icon = "chart", action = "show or hide" }):next(function(item, _, next_cx)
		if item ~= nil and next_cx ~= nil then
			toggle_badge(next_cx, item.badge)
			choose_providers(next_cx)
		end
	end)
end

if uses_fixture then
	shown.data = read_fixture(fixture_path)
	shown.history = history_fixture_path ~= nil and history_fixture_path ~= "" and read_fixture(history_fixture_path) or nil
	shown.fetched_at = shown.data ~= nil and shown.data.generatedAt or nil
	shown.loading = false
else
	local answer = stored("usage")
	if type(answer) == "table" and type(answer.at) == "number" and type(answer.data) == "table" then
		show(answer)
	end
end
rebuild()

tern.command({
	id = "providers",
	title = "Choose usage providers",
	icon = "chart",
	run = choose_providers,
})

tern.timer(0, redraw)
if not uses_fixture then
	poll()
	tern.timer(TICK_MS, tick)
end
