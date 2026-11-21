local S = {}

local function color(level)
	return "var(--ur-" .. level .. ")"
end

local function row_values(row)
	if row.dot then
		return "--dot:block"
	elseif row.fill == nil then
		return nil
	end
	local values = string.format("--f:%.3f;--c:%s", row.fill, color(row.level))
	if row.level ~= "ok" and row.level ~= "off" then
		values = values .. ";--vc:" .. color(row.level)
	end
	return values
end

function S.render(states)
	local rules = {}
	for _, state in ipairs(states) do
		table.insert(rules, string.format(
			"#widgetbar .wg[data-widget='usage-rings/%s']{--f:%.1f%%;--c:%s;--pl:%s}",
			state.id,
			(state.fill or 0) * 100,
			color(state.level),
			color("label-" .. state.level)
		))
		for index, row in ipairs(state.rows) do
			local values = row_values(row)
			if values ~= nil then
				table.insert(rules, string.format(".wgc[data-widget='usage-rings/%s'] .wgc-row:nth-child(%d){%s}", state.id, index, values))
			end
		end
	end
	return table.concat(rules, "\n")
end

return S
