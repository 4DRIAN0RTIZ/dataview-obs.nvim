local M = {}

local ns = vim.api.nvim_create_namespace("dataview")

-- bufnr → { [block_end_lnum] = { links = string[] } }
local _rendered = {}

local function execute_query(query_str)
	local ok, ast = pcall(require("dataview.parser").parse, query_str)
	if not ok then return { "> Parse error: " .. tostring(ast) } end
	local ok2, rows = pcall(require("dataview.executor").run, ast)
	if not ok2 then return { "> Exec error: " .. tostring(rows) } end
	local r = require("dataview.renderer")
	if ast.type == "TABLE" then return r.render_table(rows, ast.fields) end
	if ast.type == "TASK"  then return r.render_task(rows) end
	local field = ast.fields[1] and ast.fields[1].name or nil
	return r.render_list(rows, field)
end

local function extract_links(lines)
	local links, seen = {}, {}
	for _, line in ipairs(lines) do
		for raw in line:gmatch("%[%[([^%]|]+)|?[^%]]*%]%]") do
			local target = vim.trim(raw)
			if not seen[target] then
				seen[target] = true
				table.insert(links, target)
			end
		end
	end
	return links
end

local function open_link(target)
	local vault = require("dataview").get_config().vault
	if vault then
		local path = vault .. "/" .. target:gsub("%.md$", "") .. ".md"
		if vim.fn.filereadable(path) == 1 then
			vim.cmd("e " .. vim.fn.fnameescape(path))
			return
		end
	end
	-- fallback: let obsidian.nvim resolve it
	vim.cmd("Obsidian open " .. vim.fn.fnameescape(target))
end

function M.render_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
	_rendered[bufnr] = {}

	local lines    = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local in_block = false
	local query_lines = {}

	for i, line in ipairs(lines) do
		local lnum = i - 1
		if not in_block and line:match("^```dataview%s*$") then
			in_block    = true
			query_lines = {}
		elseif in_block and line:match("^```%s*$") then
			in_block = false

			local result = execute_query(table.concat(query_lines, "\n"))
			local sep    = string.rep("─", 56)
			local virt   = { { { sep, "Comment" } } }
			for _, rl in ipairs(result) do
				table.insert(virt, { { rl, "Normal" } })
			end
			table.insert(virt, { { sep, "Comment" } })

			vim.api.nvim_buf_set_extmark(bufnr, ns, lnum, 0, {
				virt_lines       = virt,
				virt_lines_above = false,
			})

			_rendered[bufnr][lnum] = { links = extract_links(result) }
		elseif in_block then
			table.insert(query_lines, line)
		end
	end
end

function M.pick_links(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local blocks = _rendered[bufnr] or {}

	-- Collect all unique links across all blocks
	local all_links, seen = {}, {}
	for _, block in pairs(blocks) do
		for _, link in ipairs(block.links) do
			if not seen[link] then
				seen[link] = true
				table.insert(all_links, link)
			end
		end
	end

	if #all_links == 0 then
		vim.notify("[dataview] No links in rendered blocks", vim.log.levels.WARN)
		return
	end

	-- Use Telescope if available, else vim.ui.select
	local ok, pickers   = pcall(require, "telescope.pickers")
	local ok2, finders  = pcall(require, "telescope.finders")
	local ok3, conf     = pcall(require, "telescope.config")
	local ok4, actions  = pcall(require, "telescope.actions")
	local ok5, astate   = pcall(require, "telescope.actions.state")

	if ok and ok2 and ok3 and ok4 and ok5 then
		pickers.new({}, {
			prompt_title = "Dataview Links",
			finder       = finders.new_table({ results = all_links }),
			sorter       = conf.values.generic_sorter({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)
					open_link(astate.get_selected_entry().value)
				end)
				return true
			end,
		}):find()
	else
		vim.ui.select(all_links, { prompt = "Dataview Links" }, function(choice)
			if choice then open_link(choice) end
		end)
	end
end

function M.query_float()
	vim.ui.input({ prompt = "Dataview > " }, function(input)
		if not input or input == "" then return end
		local result_lines = execute_query(input)

		local max_w = 0
		for _, l in ipairs(result_lines) do
			if #l > max_w then max_w = #l end
		end

		local width  = math.min(math.max(max_w + 4, 50), math.floor(vim.o.columns * 0.85))
		local height = math.min(#result_lines + 2, math.floor(vim.o.lines * 0.7))
		local row    = math.floor((vim.o.lines - height) / 2)
		local col    = math.floor((vim.o.columns - width) / 2)

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, result_lines)
		vim.api.nvim_set_option_value("filetype",   "markdown", { buf = buf })
		vim.api.nvim_set_option_value("modifiable", false,      { buf = buf })
		vim.api.nvim_set_option_value("bufhidden",  "wipe",     { buf = buf })

		local win = vim.api.nvim_open_win(buf, true, {
			relative  = "editor",
			row = row, col = col,
			width = width, height = height,
			style = "minimal", border = "rounded",
			title = " Dataview ", title_pos = "center",
		})

		vim.api.nvim_set_option_value("wrap",         true, { win = win })
		vim.api.nvim_set_option_value("conceallevel", 2,    { win = win })

		vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
		vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true) end, { buffer = buf, nowait = true })
	end)
end

return M
