local M = {}

local _custom_renderers = {}

function M.register_renderer(name, fn)
	_custom_renderers[name] = fn
end

local function get_field(note, field_name)
	return require("dataview.executor").get_field(note, field_name)
end

local function pad(s, n)
	s = tostring(s or "")
	if #s >= n then return s end
	return s .. string.rep(" ", n - #s)
end

function M.render_table(rows, fields)
	if _custom_renderers["table"] then
		return _custom_renderers["table"](rows, fields)
	end

	if #rows == 0 then
		return { "> No results." }
	end

	local headers = { "File" }
	for _, f in ipairs(fields) do
		table.insert(headers, f.alias or f.name)
	end

	local rows_data = {}
	for _, note in ipairs(rows) do
		local row = { tostring(get_field(note, "file.link") or "") }
		for _, f in ipairs(fields) do
			table.insert(row, tostring(get_field(note, f.name) or ""))
		end
		table.insert(rows_data, row)
	end

	local widths = {}
	for i, h in ipairs(headers) do
		widths[i] = #h
	end
	for _, row in ipairs(rows_data) do
		for i, cell in ipairs(row) do
			widths[i] = math.max(widths[i] or 0, #cell)
		end
	end

	local lines = {}

	local header_parts = {}
	for i, h in ipairs(headers) do
		table.insert(header_parts, pad(h, widths[i]))
	end
	table.insert(lines, "| " .. table.concat(header_parts, " | ") .. " |")

	local sep_parts = {}
	for i = 1, #headers do
		table.insert(sep_parts, string.rep("-", widths[i]))
	end
	table.insert(lines, "| " .. table.concat(sep_parts, " | ") .. " |")

	for _, row in ipairs(rows_data) do
		local cell_parts = {}
		for i, cell in ipairs(row) do
			table.insert(cell_parts, pad(cell, widths[i]))
		end
		table.insert(lines, "| " .. table.concat(cell_parts, " | ") .. " |")
	end

	return lines
end

function M.render_list(rows, field)
	if _custom_renderers["list"] then
		return _custom_renderers["list"](rows, field)
	end

	if #rows == 0 then
		return { "> No results." }
	end

	local lines = {}
	for _, note in ipairs(rows) do
		local link = tostring(get_field(note, "file.link") or "")
		if field then
			local val = tostring(get_field(note, field) or "")
			table.insert(lines, "- " .. link .. " :: " .. val)
		else
			table.insert(lines, "- " .. link)
		end
	end
	return lines
end

function M.render_task(rows)
	if _custom_renderers["task"] then
		return _custom_renderers["task"](rows)
	end

	if #rows == 0 then
		return { "> No results." }
	end

	local lines = {}
	for _, note in ipairs(rows) do
		local link = tostring(get_field(note, "file.link") or "")
		local status = note.frontmatter.estado or note.frontmatter.status or note.frontmatter.done or " "
		local done = (status == "done" or status == "x" or status == true or status == "true")
		table.insert(lines, "- [" .. (done and "x" or " ") .. "] " .. link)
	end
	return lines
end

return M
