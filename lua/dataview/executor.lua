local M = {}

local _custom_functions = {}

function M.register_function(name, fn)
	_custom_functions[name] = fn
end

local _stem_counts = nil

local function stem_counts()
	if _stem_counts then return _stem_counts end
	_stem_counts = {}
	for _, n in ipairs(require("dataview.index").get_all()) do
		local s = vim.fn.fnamemodify(n.path, ":t:r")
		_stem_counts[s] = (_stem_counts[s] or 0) + 1
	end
	return _stem_counts
end

vim.api.nvim_create_autocmd("User", {
	pattern = "DataviewIndexReady",
	callback = function() _stem_counts = nil end,
})

function M.get_field(note, field_name)
	if field_name == "file.link" then
		local stem = vim.fn.fnamemodify(note.path, ":t:r")
		if (stem_counts()[stem] or 0) > 1 then
			return "[[" .. note.rel_path:gsub("%.md$", "") .. "]]"
		end
		return "[[" .. stem .. "]]"
	elseif field_name == "file.name" then
		return vim.fn.fnamemodify(note.path, ":t:r")
	elseif field_name == "file.path" then
		return note.rel_path
	elseif field_name == "file.folder" then
		return vim.fn.fnamemodify(note.rel_path, ":h")
	end

	local val = note.frontmatter[field_name]
	if type(val) == "table" then
		return table.concat(val, ", ")
	end
	return val
end

local function eval_fn(note, cond)
	local fn_name = cond.fn
	local args = cond.args

	if _custom_functions[fn_name] then
		return _custom_functions[fn_name](note, args)
	end

	if fn_name == "contains" then
		local raw = note.frontmatter[args[1]]
		local search = args[2] or ""
		if type(raw) == "table" then
			for _, v in ipairs(raw) do
				if tostring(v) == search then return true end
			end
			return false
		end
		local s = tostring(raw or "")
		return s:find(search, 1, true) ~= nil
	end

	if fn_name == "startswith" then
		local val = tostring(M.get_field(note, args[1]) or "")
		return val:sub(1, #(args[2] or "")) == (args[2] or "")
	end

	if fn_name == "endswith" then
		local val = tostring(M.get_field(note, args[1]) or "")
		local suffix = args[2] or ""
		return val:sub(- #suffix) == suffix
	end

	return false
end

local function eval_condition(note, cond)
	if not cond then return true end

	if cond.type == "logical" then
		local left = eval_condition(note, cond.left)
		if cond.op == "AND" and not left then return false end
		if cond.op == "OR" and left then return true end
		return eval_condition(note, cond.right)
	end

	if cond.type == "fn" then
		return eval_fn(note, cond)
	end

	if cond.type == "exists" then
		return note.frontmatter[cond.field] ~= nil
	end

	if cond.type == "compare" then
		local val = M.get_field(note, cond.field)
		local target = cond.value
		local sv = tostring(val or "")
		local st = tostring(target or "")
		local nv = tonumber(val)
		local nt = tonumber(target)

		if cond.op == "=" then
			return sv == st
		elseif cond.op == "!=" then
			return sv ~= st
		elseif cond.op == "<" then
			return (nv or 0) < (nt or 0)
		elseif cond.op == ">" then
			return (nv or 0) > (nt or 0)
		elseif cond.op == "<=" then
			return (nv or 0) <= (nt or 0)
		elseif cond.op == ">=" then
			return (nv or 0) >= (nt or 0)
		end
	end

	return true
end

local function matches_from(note, from)
	if from.type == "all" then return true end

	if from.type == "folder" then
		local folder = from.value:gsub("/$", "")
		return note.rel_path:match("^" .. vim.pesc(folder) .. "/") ~= nil
	end

	if from.type == "tag" then
		local tags = note.frontmatter.tags or {}
		if type(tags) == "string" then tags = { tags } end
		for _, t in ipairs(tags) do
			if t == from.value then return true end
		end
		return false
	end

	return true
end

function M.run(ast)
	local index = require("dataview.index")
	local notes = index.get_all()
	local results = {}

	for _, note in ipairs(notes) do
		if matches_from(note, ast.from) and eval_condition(note, ast.where) then
			table.insert(results, note)
		end
	end

	if ast.sort and ast.sort.field then
		local field = ast.sort.field
		local asc = ast.sort.dir ~= "DESC"
		table.sort(results, function(a, b)
			local va = tostring(M.get_field(a, field) or "")
			local vb = tostring(M.get_field(b, field) or "")
			return asc and (va < vb) or (va > vb)
		end)
	end

	if ast.limit then
		while #results > ast.limit do
			table.remove(results)
		end
	end

	return results
end

return M
