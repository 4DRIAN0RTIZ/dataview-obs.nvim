local M = {}

M._index = {}
M._vault = nil

local function parse_frontmatter(lines)
	local fm = {}
	local in_fm = false
	local current_key = nil
	local current_is_list = false

	for i, line in ipairs(lines) do
		if i == 1 and line == "---" then
			in_fm = true
		elseif in_fm then
			if line == "---" then
				break
			end
			local item = line:match("^%s+%-%s*(.*)$")
			if item ~= nil and current_is_list then
				table.insert(fm[current_key], item)
			else
				current_is_list = false
				local key, val = line:match("^([%w_%-]+):%s*(.*)$")
				if key then
					current_key = key
					if val == "[]" then
						fm[key] = {}
					elseif val:match("^%[.+%]$") then
						local lst = {}
						for it in val:match("^%[(.+)%]$"):gmatch("[^,]+") do
							table.insert(lst, (vim.trim(it):gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")))
						end
						fm[key] = lst
					elseif val == "" then
						fm[key] = {}
						current_is_list = true
					else
						local unquoted = val:match('^"(.*)"$') or val:match("^'(.*)'$") or val
						fm[key] = tonumber(unquoted) or unquoted
					end
				end
			end
		end
	end

	return fm
end

local function scan_dir(dir, callback)
	local handle = vim.loop.fs_scandir(dir)
	if not handle then return end

	while true do
		local name, type = vim.loop.fs_scandir_next(handle)
		if not name then break end

		local full = dir .. "/" .. name
		if type == "directory" and not name:match("^%.") and name ~= ".obsidian" then
			scan_dir(full, callback)
		elseif type == "file" and name:match("%.md$") then
			callback(full)
		end
	end
end

function M.build(vault_path)
	M._vault = vault_path
	M._index = {}

	vim.defer_fn(function()
		local count = 0
		scan_dir(vault_path, function(path)
			local lines = vim.fn.readfile(path, "", 50)
			local fm = parse_frontmatter(lines)
			local rel = path:sub(#vault_path + 2)
			M._index[path] = {
				path        = path,
				rel_path    = rel,
				frontmatter = fm,
			}
			count = count + 1
		end)
		vim.notify(string.format("[dataview] indexed %d notes", count), vim.log.levels.INFO)
		vim.api.nvim_exec_autocmds("User", { pattern = "DataviewIndexReady" })
	end, 300)
end

function M.get_all()
	local out = {}
	for _, entry in pairs(M._index) do
		table.insert(out, entry)
	end
	return out
end

function M.get_vault()
	return M._vault
end

return M
