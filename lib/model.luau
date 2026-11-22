local M = {}

local NBSP = "\u{A0}"
local ZERO_WIDTH_SPACE = "\u{200B}"

local function starts_with(s, prefix)
	return string.sub(s, 1, #prefix) == prefix
end

local function as_number(value)
	return type(value) == "number" and value or nil
end

local KNOWN_BADGES = {
	{ id = "claude", name = "Claude", icon = "provider:anthropic", prefixes = { "anthropic" } },
	{ id = "codex", name = "Codex", icon = "provider:openai", prefixes = { "openai-codex" } },
	{
		id = "gemini",
		name = "Gemini",
		icon = "provider:google-gemini-cli",
		prefixes = { "google-antigravity", "google-gemini" },
		keeps_limit = function(provider, limit)
			return provider ~= "google-antigravity" or starts_with(string.lower(limit.label or ""), "gemini")
		end,
		ignores_capacity = function(provider)
			return provider == "google-antigravity"
		end,
	},
	{ id = "opencode", name = "OpenCode", icon = "provider:opencode", prefixes = { "opencode" } },
	{ id = "grok", name = "Grok", icon = "provider:xai", prefixes = { "xai" } },
}

local function accepts(badge, provider)
	for _, prefix in ipairs(badge.prefixes or {}) do
		if starts_with(provider, prefix) then
			return true
		end
	end
	for _, exact in ipairs(badge.providers or {}) do
		if provider == exact then
			return true
		end
	end
	return false
end

local function badge_for(badges, provider)
	if type(provider) ~= "string" then
		return nil
	end
	for _, badge in ipairs(badges) do
		if accepts(badge, provider) then
			return badge
		end
	end
	return nil
end

local function title_case(provider)
	local words = {}
	for word in string.gmatch(provider, "[^%-_%s]+") do
		table.insert(words, string.upper(string.sub(word, 1, 1)) .. string.sub(word, 2))
	end
	return table.concat(words, " ")
end

local function widget_id(provider)
	local id = string.gsub(string.lower(provider), "[^a-z0-9]+", "-")
	if string.match(id, "^[a-z]") == nil then
		id = "p-" .. id
	end
	return string.sub(id, 1, 32)
end

local function badges_for(data, placed)
	local badges, taken, providers = {}, {}, {}
	for _, badge in ipairs(KNOWN_BADGES) do
		table.insert(badges, badge)
		taken[badge.id] = true
	end
	for _, list in ipairs({ "reports", "accountsWithoutUsage" }) do
		for _, item in ipairs((data or {})[list] or {}) do
			if type(item.provider) == "string" and item.provider ~= "" and badge_for(KNOWN_BADGES, item.provider) == nil then
				providers[item.provider] = true
			end
		end
	end
	local unknown = {}
	for provider in pairs(providers) do
		table.insert(unknown, provider)
	end
	table.sort(unknown)
	for _, id in ipairs(placed or {}) do
		table.insert(unknown, id)
	end
	for _, provider in ipairs(unknown) do
		local id = widget_id(provider)
		if not taken[id] then
			taken[id] = true
			table.insert(badges, { id = id, name = title_case(provider), icon = "provider:" .. provider, providers = { provider } })
		end
	end
	return badges
end

local function clamp01(x)
	return math.max(0, math.min(1, x))
end

local function percent(fraction)
	return math.floor(clamp01(fraction) * 100 + 0.5)
end

local function level(fraction)
	if fraction == nil then
		return "off"
	elseif fraction >= 0.95 then
		return "bad"
	elseif fraction >= 0.8 then
		return "hot"
	elseif fraction >= 0.5 then
		return "warn"
	end
	return "ok"
end

local function pad_left(s, width)
	return string.rep(NBSP, math.max(0, width - utf8.len(s))) .. s
end

local function pad_right(s, width)
	return s .. string.rep(NBSP, math.max(0, width - utf8.len(s)))
end

local function truncate(s, length)
	local count = utf8.len(s)
	if count == nil then
		return string.sub(s, 1, length)
	elseif count <= length then
		return s
	end
	return (string.gsub(string.sub(s, 1, utf8.offset(s, length) - 1), "%s+$", "")) .. "…"
end

local function without_key_separator(s)
	return (string.gsub(s, ":%s", ", "))
end

local function capitalize(s)
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

local function plural(count, noun)
	return string.format("%d %s%s", count, noun, count == 1 and "" or "s")
end

local function time_until(at, now)
	if at == nil then
		return nil
	end
	local minutes = math.floor((at - now) / 60000)
	if minutes <= 0 then
		return "now"
	end
	local days = minutes // 1440
	local hours = (minutes % 1440) // 60
	if days > 0 then
		return string.format("%dd%dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh%02dm", hours, minutes % 60)
	end
	return string.format("%dm", minutes)
end

local function time_since(ms)
	local minutes = math.floor(ms / 60000)
	if minutes < 1 then
		return "just now"
	elseif minutes < 60 then
		return string.format("%d min ago", minutes)
	elseif minutes < 2880 then
		return string.format("%d h ago", minutes // 60)
	end
	return string.format("%d d ago", minutes // 1440)
end

local function reset_phrase(resets_at, now)
	local reset = time_until(resets_at, now)
	if reset == nil then
		return nil
	elseif reset == "now" then
		return "resets now"
	end
	return "resets in " .. reset
end

local function aligned_value(used, resets_at, now)
	if used == nil then
		return "no data"
	end
	local tail = pad_right((string.gsub(reset_phrase(resets_at, now) or "no reset time", " ", NBSP)), 16)
	return ZERO_WIDTH_SPACE .. pad_left(string.format("%d%%", percent(used)), 4) .. NBSP .. "·" .. NBSP .. tail .. ZERO_WIDTH_SPACE
end

local function normal_window(id)
	local lowered = string.lower(id or "")
	local weeks = string.match(lowered, "^(%d+)w$")
	if weeks then
		return tostring(tonumber(weeks) * 7) .. "d"
	end
	return lowered
end

local function window_name(id, label, fallback)
	local count, unit = string.match(id, "^(%d+)([hd])$")
	if count then
		return count .. unit
	elseif id == "monthly" then
		return "Monthly"
	elseif label ~= nil and label ~= "" then
		return label
	elseif id ~= "" then
		return id
	end
	return fallback
end

local function window_id_from_label(label)
	local lowered = string.lower(label or "")
	local hours = string.match(lowered, "^(%d+)%s*h")
	if hours then
		return hours .. "h"
	elseif string.find(lowered, "week") or string.find(lowered, "7%s*d") then
		return "7d"
	elseif string.find(lowered, "month") then
		return "monthly"
	end
	return lowered
end

local function id_words_the_window_omits(id, window)
	local said = string.lower(window or "")
	local words = {}
	for word in string.gmatch(string.lower(string.match(tostring(id or ""), "([^:]*)$")), "[^%-_%s]+") do
		if string.find(said, word, 1, true) == nil then
			table.insert(words, word)
		end
	end
	return words
end

local function label_words_the_window_omits(label, window)
	local said = string.lower(window or "")
	local words = {}
	for word in string.gmatch(label or "", "%w+") do
		if string.find(said, string.lower(word), 1, true) == nil then
			table.insert(words, word)
		end
	end
	return table.concat(words, " ")
end

local function used_fraction(amount)
	if amount == nil then
		return nil
	elseif type(amount.usedFraction) == "number" then
		return clamp01(amount.usedFraction)
	elseif type(amount.remainingFraction) == "number" then
		return clamp01(1 - amount.remainingFraction)
	elseif type(amount.limit) == "number" and amount.limit > 0 then
		if type(amount.used) == "number" then
			return clamp01(amount.used / amount.limit)
		elseif type(amount.remaining) == "number" then
			return clamp01(1 - amount.remaining / amount.limit)
		end
	end
	return nil
end

local function amount_text(value, unit)
	local size = math.abs(value)
	local whole = size >= 100 or size == math.floor(size)
	local number = whole and string.format("%d", math.floor(size + 0.5)) or string.format("%.2f", size)
	local sign = value < 0 and "-" or ""
	if unit == "usd" then
		return sign .. "$" .. number
	elseif type(unit) == "string" and unit ~= "" and unit ~= "percent" then
		return sign .. number .. " " .. unit
	end
	return sign .. number
end

local function counted_use(limit)
	if limit.status == "exhausted" then
		return 1
	end
	return limit.used
end

local function email_name(account)
	local email = account.email
	if type(email) == "string" and email ~= "" then
		return truncate(string.match(email, "^([^@]+)") or email, 20)
	end
	return nil
end

local function account_from_report(report, badge)
	local details = report.metadata or {}
	local plan = details.subscriptionPlan or details.planType
	local plan_word = type(plan) == "string" and string.lower(plan) or nil
	local limits = {}
	for _, limit in ipairs(report.limits or {}) do
		if badge.keeps_limit == nil or badge.keeps_limit(report.provider, limit) then
			local window = type(limit.window) == "table" and limit.window or {}
			local id = normal_window(window.id)
			local window_words = (window.label or "") .. " " .. (window.id or "") .. " " .. id
			local tier = type((limit.scope or {}).tier) == "string" and string.lower(limit.scope.tier) or nil
			local amount = type(limit.amount) == "table" and limit.amount or {}
			local used = used_fraction(amount)
			local has_balance = used == nil and type(amount.remaining) == "number"
			table.insert(limits, {
				id_words = id_words_the_window_omits(limit.id, window_words),
				remainder = label_words_the_window_omits(limit.label, window_words),
				window = id,
				name = window_name(id, window.label, limit.label or "Usage"),
				tier = tier ~= plan_word and tier or nil,
				used = used,
				left = has_balance and { amount = amount.remaining, unit = amount.unit } or nil,
				status = limit.status,
				resets_at = as_number(window.resetsAt),
			})
		end
	end
	return {
		name = email_name(details),
		credential = type(details.credentialId) == "number" and details.credentialId or nil,
		plan = plan,
		limits = limits,
	}
end

local function accounts_from_report(data, badge, badges)
	local accounts, providers = {}, {}
	for _, report in ipairs(data.reports or {}) do
		if badge_for(badges, report.provider) == badge then
			providers[report.provider] = true
			local account = account_from_report(report, badge)
			if #account.limits > 0 or #(report.limits or {}) == 0 then
				table.insert(accounts, account)
			end
		end
	end
	for _, account in ipairs(data.accountsWithoutUsage or {}) do
		if badge_for(badges, account.provider) == badge then
			providers[account.provider] = true
			table.insert(accounts, { name = email_name(account), limits = {} })
		end
	end
	return accounts, providers
end

local function accounts_from_history(history, badge, badges)
	local by_account, order = {}, {}
	for _, entry in ipairs((history or {}).entries or {}) do
		if badge_for(badges, entry.provider) == badge and (badge.keeps_limit == nil or badge.keeps_limit(entry.provider, entry)) then
			local key = entry.accountKey or entry.email or entry.accountId or "?"
			local account = by_account[key]
			if account == nil then
				account = { name = email_name(entry), limits = {} }
				by_account[key] = account
				table.insert(order, key)
			end
			local limit_id = entry.limitId or entry.label or "?"
			local recorded_at = as_number(entry.recordedAt) or 0
			local known = account.limits[limit_id]
			if known == nil or recorded_at > known.recorded_at then
				local window = window_id_from_label(entry.windowLabel)
				local window_words = (entry.windowLabel or "") .. " " .. window
				account.limits[limit_id] = {
					id_words = id_words_the_window_omits(entry.limitId, window_words),
					remainder = label_words_the_window_omits(entry.label, window_words),
					order = tostring(limit_id),
					window = window,
					name = window_name(window, entry.windowLabel, entry.label or "Usage"),
					used = type(entry.usedFraction) == "number" and clamp01(entry.usedFraction) or nil,
					status = entry.status,
					resets_at = as_number(entry.resetsAt),
					recorded_at = recorded_at,
				}
			end
		end
	end
	local accounts, newest = {}, nil
	for _, key in ipairs(order) do
		local limits = {}
		for _, limit in pairs(by_account[key].limits) do
			table.insert(limits, limit)
			if newest == nil or limit.recorded_at > newest then
				newest = limit.recorded_at
			end
		end
		table.sort(limits, function(a, b)
			if a.name ~= b.name then
				return a.name < b.name
			elseif #a.id_words ~= #b.id_words then
				return #a.id_words < #b.id_words
			end
			return a.order < b.order
		end)
		table.insert(accounts, { name = by_account[key].name, limits = limits })
	end
	return accounts, newest
end

local function unusable_credentials(data, badge, badges)
	local credentials = {}
	for _, credential in ipairs(data.disabledCredentials or {}) do
		if badge_for(badges, credential.provider) == badge then
			local cause = string.lower(credential.cause or "")
			local signed_out = string.find(cause, "refresh") or string.find(cause, "expired") or string.find(cause, "invalid_grant")
			table.insert(credentials, { name = email_name(credential) or "An account", problem = signed_out and "signed out" or "disabled" })
		end
	end
	return credentials
end

local function order_and_label(accounts)
	local all_have_credentials = #accounts > 0
	for _, account in ipairs(accounts) do
		all_have_credentials = all_have_credentials and account.credential ~= nil
	end
	if all_have_credentials then
		table.sort(accounts, function(a, b)
			return a.credential < b.credential
		end)
	end
	local uses = {}
	for i, account in ipairs(accounts) do
		account.label = account.name or ("Account " .. tostring(i))
		uses[account.label] = (uses[account.label] or 0) + 1
	end
	for i, account in ipairs(accounts) do
		if uses[account.label] > 1 then
			account.label = account.label .. " (" .. tostring(i) .. ")"
		end
	end
end

local function soonest_reset(accounts, window, tier, now)
	local soonest = nil
	for _, account in ipairs(accounts) do
		for _, limit in ipairs(account.limits) do
			local matches = limit.window == window and limit.tier == tier
			if matches and limit.resets_at ~= nil and limit.resets_at > now and (soonest == nil or limit.resets_at < soonest) then
				soonest = limit.resets_at
			end
		end
	end
	return soonest
end

local function tiers_of(accounts)
	local tiers = {}
	for _, account in ipairs(accounts) do
		for _, limit in ipairs(account.limits) do
			if limit.tier ~= nil then
				tiers[limit.tier] = true
			end
		end
	end
	return tiers
end

local function pool_from_capacity(data, providers, accounts, now)
	local windows, tiers = {}, tiers_of(accounts)
	for provider in pairs(providers) do
		for _, capacity in ipairs((data.capacity or {})[provider] or {}) do
			if type(capacity.accounts) == "number" and capacity.accounts > 0 and type(capacity.usedAccounts) == "number" then
				local meter = type(capacity.meter) == "string" and string.lower(capacity.meter) or nil
				local tier = (meter ~= nil and tiers[meter]) and meter or nil
				local window = normal_window(capacity.window)
				local name = window_name(window, capacity.window, "Usage")
				table.insert(windows, {
					name = tier ~= nil and (capitalize(tier) .. " " .. name) or name,
					used = clamp01(capacity.usedAccounts / capacity.accounts),
					resets_at = soonest_reset(accounts, window, tier, now),
					narrow = tier ~= nil,
				})
			end
		end
	end
	return windows
end

local function pool_from_limits(accounts, now)
	local groups, order = {}, {}
	for _, account in ipairs(accounts) do
		for _, limit in ipairs(account.limits) do
			local used = counted_use(limit)
			if used ~= nil then
				local group = groups[limit.shown]
				if group == nil then
					group = { narrow = limit.narrow, sum = 0, count = 0 }
					groups[limit.shown] = group
					table.insert(order, limit.shown)
				end
				group.sum = group.sum + used
				group.count = group.count + 1
				if limit.resets_at ~= nil and limit.resets_at > now and (group.resets_at == nil or limit.resets_at < group.resets_at) then
					group.resets_at = limit.resets_at
				end
			end
		end
	end
	local windows = {}
	for _, name in ipairs(order) do
		local group = groups[name]
		table.insert(windows, { name = name, used = clamp01(group.sum / group.count), resets_at = group.resets_at, narrow = group.narrow })
	end
	return windows
end

local function pool_of(data, badge, providers, accounts, from_history, now)
	if #accounts == 0 then
		return {}
	end
	local capacity_counts = not from_history
	for provider in pairs(providers) do
		if badge.ignores_capacity ~= nil and badge.ignores_capacity(provider) then
			capacity_counts = false
		end
	end
	local pool = capacity_counts and pool_from_capacity(data, providers, accounts, now) or {}
	if #pool == 0 then
		pool = pool_from_limits(accounts, now)
	end
	return pool
end

local function tightest_window(pool)
	local tightest, tightest_of_any = nil, nil
	for _, window in ipairs(pool) do
		if tightest_of_any == nil or window.used > tightest_of_any.used then
			tightest_of_any = window
		end
		if not window.narrow and (tightest == nil or window.used > tightest.used) then
			tightest = window
		end
	end
	return tightest or tightest_of_any
end

local function all_differ(limits, field)
	local seen = {}
	for _, limit in ipairs(limits) do
		if seen[limit[field]] then
			return false
		end
		seen[limit[field]] = true
	end
	return true
end

local function set_own_words(limits)
	local holders = {}
	for _, limit in ipairs(limits) do
		for _, word in ipairs(limit.id_words) do
			holders[word] = (holders[word] or 0) + 1
		end
	end
	for _, limit in ipairs(limits) do
		local own = {}
		for _, word in ipairs(limit.id_words) do
			if holders[word] < #limits then
				table.insert(own, word)
			end
		end
		limit.distinction = table.concat(own, "-")
	end
end

local function name_limits(account)
	local sharing = {}
	for _, limit in ipairs(account.limits) do
		local key = limit.name .. "|" .. (limit.tier or "")
		sharing[key] = sharing[key] or {}
		table.insert(sharing[key], limit)
	end
	for _, same_name in pairs(sharing) do
		local tells_apart = nil
		if #same_name > 1 then
			set_own_words(same_name)
			tells_apart = (all_differ(same_name, "distinction") or not all_differ(same_name, "remainder")) and "distinction" or "remainder"
		end
		for _, limit in ipairs(same_name) do
			local suffix = tells_apart ~= nil and limit[tells_apart] or ""
			local name = limit.tier ~= nil and (capitalize(limit.tier) .. " " .. limit.name) or limit.name
			limit.shown = suffix ~= "" and (name .. " " .. suffix) or name
			limit.narrow = limit.tier ~= nil or suffix ~= ""
		end
	end
end

local function balance_left(accounts)
	local total, unit = nil, nil
	for _, account in ipairs(accounts) do
		for _, limit in ipairs(account.limits) do
			if limit.left ~= nil and (total == nil or limit.left.unit == unit) then
				total = (total or 0) + limit.left.amount
				unit = limit.left.unit
			end
		end
	end
	return total ~= nil and { amount = total, unit = unit } or nil
end

local function loading_state(badge)
	return {
		id = badge.id,
		name = badge.name,
		icon = badge.icon,
		summary = "reading omp",
		has_limits = false,
		view = { text = "…", tone = "quiet", title = "Reading usage from omp…" },
		level = "off",
		rows = { {} },
	}
end

local function state_for(badge, badges, input)
	local now = input.now
	local accounts, providers, from_history, newest = {}, {}, false, nil
	local unusable = {}
	if input.data ~= nil then
		accounts, providers = accounts_from_report(input.data, badge, badges)
		unusable = unusable_credentials(input.data, badge, badges)
	end
	local has_limits = false
	for _, account in ipairs(accounts) do
		has_limits = has_limits or #account.limits > 0
	end
	if not has_limits and input.history ~= nil then
		local recorded, recorded_at = accounts_from_history(input.history, badge, badges)
		if #recorded > 0 then
			accounts, newest, from_history = recorded, recorded_at, true
		end
	end
	order_and_label(accounts)
	for _, account in ipairs(accounts) do
		name_limits(account)
	end

	local pool = pool_of(input.data, badge, providers, accounts, from_history, now)
	local tightest = tightest_window(pool)
	local used = tightest ~= nil and tightest.used or nil
	local used_up = used ~= nil and percent(used) >= 100
	local left = used == nil and balance_left(accounts) or nil
	local text = "n/a"
	if used ~= nil then
		text = string.format("%d%%", percent(used))
		if used_up then
			text = time_until(tightest.resets_at, now) or text
		end
	elseif left ~= nil then
		text = amount_text(left.amount, left.unit == "usd" and "usd" or nil)
	end

	local flags = {}
	if used == nil and #accounts == 0 then
		table.insert(flags, "quiet")
	end
	if #unusable > 0 then
		table.insert(flags, "dis")
	end
	if from_history or input.error ~= nil then
		table.insert(flags, "old")
	end

	local lines, rows = {}, {}
	local function heading(line, row)
		table.insert(lines, without_key_separator(line))
		table.insert(rows, row or {})
	end
	local function meter(name, fraction, resets_at, left)
		local value = left ~= nil and (amount_text(left.amount, left.unit) .. NBSP .. "left") or aligned_value(fraction, resets_at, now)
		table.insert(lines, without_key_separator(truncate(name, 14)) .. ": " .. value)
		table.insert(rows, left ~= nil and { bar = false } or { fill = fraction or 0, level = level(fraction) })
	end
	if #accounts > 1 and #pool > 0 then
		heading(string.format("All %d accounts", #accounts))
		for _, window in ipairs(pool) do
			meter(window.name, window.used, window.resets_at)
		end
	end
	for _, account in ipairs(accounts) do
		heading(account.plan ~= nil and (account.label .. " · " .. capitalize(tostring(account.plan))) or account.label)
		if #account.limits == 0 then
			meter("Usage", nil, nil)
		end
		for _, limit in ipairs(account.limits) do
			meter(limit.shown, counted_use(limit), limit.resets_at, limit.left)
		end
	end
	for _, credential in ipairs(unusable) do
		heading(credential.name .. " · " .. credential.problem .. ", sign in again with omp", { dot = true })
	end
	if #accounts == 0 and #unusable == 0 then
		heading("omp has no usage data for " .. badge.name)
	end
	local footer = "Not read yet"
	if from_history then
		footer = "From omp's usage history" .. ((newest or 0) > 0 and (", " .. time_since(now - newest)) or "")
	elseif input.fetched_at ~= nil then
		footer = "Updated " .. time_since(now - input.fetched_at)
	end
	if input.error ~= nil then
		footer = footer .. " · last refresh failed (" .. truncate(input.error, 40) .. ")"
	end
	heading(footer)

	local summary = "no account in omp"
	if #accounts > 0 then
		summary = plural(#accounts, "account")
		if used_up and tightest.resets_at ~= nil then
			summary = summary .. ", used up, " .. reset_phrase(tightest.resets_at, now)
		elseif used ~= nil then
			summary = summary .. string.format(", %d%% used", percent(used))
		elseif left ~= nil then
			summary = summary .. ", " .. amount_text(left.amount, left.unit) .. " left"
		else
			summary = summary .. ", no usage data"
		end
	end
	if #unusable > 0 then
		summary = (#accounts > 0 and (summary .. ", ") or "") .. tostring(#unusable) .. " signed out"
	end

	return {
		id = badge.id,
		name = badge.name,
		icon = badge.icon,
		summary = summary,
		has_limits = has_limits,
		view = { text = text, tone = #flags > 0 and table.concat(flags, " ") or nil, title = table.concat(lines, "\n") },
		fill = used,
		level = left ~= nil and "ok" or level(used),
		rows = rows,
	}
end

function M.build(input)
	local badges = badges_for(input.data, input.placed)
	local states = {}
	for _, badge in ipairs(badges) do
		table.insert(states, input.loading and loading_state(badge) or state_for(badge, badges, input))
	end
	return states
end

function M.badge_of_provider(data)
	local badges = badges_for(data)
	return function(provider)
		local badge = badge_for(badges, provider)
		return badge ~= nil and badge.id or nil
	end
end

return M
