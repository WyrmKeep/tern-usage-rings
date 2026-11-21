local M = {}

local NBSP = "\u{A0}"
local ZERO_WIDTH_SPACE = "\u{200B}"

local function starts_with(s, prefix)
	return string.sub(s, 1, #prefix) == prefix
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
	for _, list in ipairs({ "reports", "accountsWithoutUsage", "disabledCredentials" }) do
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
	if utf8.len(s) <= length then
		return s
	end
	return string.sub(s, 1, utf8.offset(s, length) - 1) .. "…"
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

local function aligned_value(used, resets_at, now)
	if used == nil then
		return "no data"
	end
	local reset = time_until(resets_at, now)
	local tail = reset ~= nil and ("resets" .. NBSP .. "in" .. NBSP .. pad_right(reset, 6)) or pad_right("no" .. NBSP .. "reset" .. NBSP .. "time", 16)
	return ZERO_WIDTH_SPACE .. pad_left(string.format("%d%%", percent(used)), 4) .. NBSP .. "·" .. NBSP .. tail .. ZERO_WIDTH_SPACE
end

local function window_name(id, label)
	local lowered = string.lower(id or "")
	local count, unit = string.match(lowered, "^(%d+)([hd])$")
	if count then
		return count .. unit
	elseif lowered == "monthly" then
		return "Monthly"
	end
	return label or id or "?"
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

local function words_only_the_id_says(id, label, window)
	local said = string.lower((label or "") .. " " .. (window or ""))
	local words = {}
	for word in string.gmatch(string.lower(string.match(id or "", "([^:]*)$")), "[^%-_%s]+") do
		if string.find(said, word, 1, true) == nil then
			table.insert(words, word)
		end
	end
	return table.concat(words, "-")
end

local function used_fraction(amount)
	if amount == nil then
		return nil
	elseif type(amount.usedFraction) == "number" then
		return clamp01(amount.usedFraction)
	elseif type(amount.remainingFraction) == "number" then
		return clamp01(1 - amount.remainingFraction)
	end
	return nil
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
	local limits = {}
	for _, limit in ipairs(report.limits or {}) do
		if badge.keeps_limit == nil or badge.keeps_limit(report.provider, limit) then
			local window = limit.window or {}
			table.insert(limits, {
				distinction = words_only_the_id_says(limit.id, limit.label, (window.label or "") .. " " .. (window.id or "")),
				window = string.lower(window.id or ""),
				name = window_name(window.id, window.label),
				tier = type((limit.scope or {}).tier) == "string" and string.lower(limit.scope.tier) or nil,
				used = used_fraction(limit.amount),
				status = limit.status,
				resets_at = window.resetsAt,
			})
		end
	end
	return {
		name = email_name(details),
		credential = type(details.credentialId) == "number" and details.credentialId or nil,
		plan = details.subscriptionPlan or details.planType,
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
			local known = account.limits[entry.limitId]
			if known == nil or (entry.recordedAt or 0) > known.recorded_at then
				local window = window_id_from_label(entry.windowLabel)
				account.limits[entry.limitId] = {
					distinction = words_only_the_id_says(entry.limitId, entry.label, entry.windowLabel),
					window = window,
					name = window_name(window, entry.windowLabel),
					used = type(entry.usedFraction) == "number" and clamp01(entry.usedFraction) or nil,
					status = entry.status,
					resets_at = entry.resetsAt,
					recorded_at = entry.recordedAt or 0,
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
			end
			return a.distinction < b.distinction
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
				local name = window_name(capacity.window, capacity.window)
				table.insert(windows, {
					name = tier ~= nil and (capitalize(tier) .. " " .. name) or name,
					used = clamp01(capacity.usedAccounts / capacity.accounts),
					resets_at = soonest_reset(accounts, string.lower(capacity.window or ""), tier, now),
					tier = tier,
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
				local key = (limit.tier or "") .. "|" .. limit.window
				local group = groups[key]
				if group == nil then
					group = { window = limit.window, name = limit.name, tier = limit.tier, sum = 0, count = 0 }
					groups[key] = group
					table.insert(order, key)
				end
				group.sum = group.sum + used
				group.count = group.count + 1
			end
		end
	end
	local windows = {}
	for _, key in ipairs(order) do
		local group = groups[key]
		table.insert(windows, {
			name = group.tier ~= nil and (capitalize(group.tier) .. " " .. group.name) or group.name,
			used = clamp01(group.sum / group.count),
			resets_at = soonest_reset(accounts, group.window, group.tier, now),
			tier = group.tier,
		})
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
	local tightest, tightest_of_any_tier = nil, nil
	for _, window in ipairs(pool) do
		if tightest_of_any_tier == nil or window.used > tightest_of_any_tier.used then
			tightest_of_any_tier = window
		end
		if window.tier == nil and (tightest == nil or window.used > tightest.used) then
			tightest = window
		end
	end
	return tightest or tightest_of_any_tier
end

local function limit_names(account)
	local shared = {}
	for _, limit in ipairs(account.limits) do
		local key = limit.name .. "|" .. (limit.tier or "")
		shared[key] = (shared[key] or 0) + 1
	end
	local names = {}
	for i, limit in ipairs(account.limits) do
		local name = limit.tier ~= nil and (capitalize(limit.tier) .. " " .. limit.name) or limit.name
		if shared[limit.name .. "|" .. (limit.tier or "")] > 1 and limit.distinction ~= "" then
			name = name .. " " .. limit.distinction
		end
		names[i] = name
	end
	return names
end

local function loading_state(badge)
	return {
		id = badge.id,
		name = badge.name,
		icon = badge.icon,
		summary = "reading omp",
		accounts = 0,
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
	local reported = #accounts
	if reported == 0 and input.history ~= nil then
		accounts, newest = accounts_from_history(input.history, badge, badges)
		from_history = #accounts > 0
	end
	order_and_label(accounts)

	local pool = pool_of(input.data, badge, providers, accounts, from_history, now)
	local tightest = tightest_window(pool)
	local used = tightest ~= nil and tightest.used or nil
	local used_up = used ~= nil and percent(used) >= 100
	local text = "n/a"
	if used ~= nil then
		text = string.format("%d%%", percent(used))
		if used_up then
			text = time_until(tightest.resets_at, now) or text
		end
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
	local function meter(name, fraction, resets_at)
		table.insert(lines, without_key_separator(truncate(name, 14)) .. ": " .. aligned_value(fraction, resets_at, now))
		table.insert(rows, { fill = fraction or 0, level = level(fraction) })
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
		local names = limit_names(account)
		for i, limit in ipairs(account.limits) do
			meter(names[i], counted_use(limit), limit.resets_at)
		end
	end
	for _, credential in ipairs(unusable) do
		heading(credential.name .. " · " .. credential.problem .. ", sign in again with omp", { dot = true })
	end
	if #accounts == 0 and #unusable == 0 then
		heading("omp has no usage data for " .. badge.name)
	end
	local footer = "Not read yet"
	if from_history and newest ~= nil then
		footer = "From omp's usage history, " .. time_since(now - newest)
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
			summary = summary .. ", used up, resets in " .. time_until(tightest.resets_at, now)
		elseif used ~= nil then
			summary = summary .. string.format(", %d%% used", percent(used))
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
		accounts = reported,
		view = { text = text, tone = #flags > 0 and table.concat(flags, " ") or nil, title = table.concat(lines, "\n") },
		fill = used,
		level = level(used),
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
