if vim.g.loaded_dataview then return end
vim.g.loaded_dataview = true

vim.api.nvim_create_user_command("DataviewQuery", function()
	require("dataview.ui").query_float()
end, { desc = "Dataview: Interactive query in float window" })

vim.api.nvim_create_user_command("DataviewRefresh", function()
	local cfg = require("dataview").get_config()
	if cfg.vault then
		require("dataview.index").build(cfg.vault)
	else
		vim.notify("[dataview] No vault configured", vim.log.levels.WARN)
	end
end, { desc = "Dataview: Rebuild note index" })

vim.api.nvim_create_user_command("DataviewRender", function()
	require("dataview.ui").render_buffer()
end, { desc = "Dataview: Render dataview blocks as virtual text" })

vim.api.nvim_create_user_command("DataviewLinks", function()
	require("dataview.ui").pick_links()
end, { desc = "Dataview: Pick a link from rendered results and open it" })

local grp = vim.api.nvim_create_augroup("DataviewAutoRender", { clear = true })

vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
	pattern  = "*.md",
	group    = grp,
	callback = function(ev)
		local cfg = require("dataview").get_config()
		if not cfg.auto_render or not cfg.vault then return end
		if not ev.file:find(vim.pesc(cfg.vault), 1, true) then return end

		local lines = vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false)
		for _, line in ipairs(lines) do
			if line:match("^```dataview%s*$") then
				vim.schedule(function()
					require("dataview.ui").render_buffer(ev.buf)
				end)
				return
			end
		end
	end,
})

vim.api.nvim_create_autocmd("User", {
	pattern  = "DataviewIndexReady",
	callback = function()
		local cfg = require("dataview").get_config()
		if not cfg.vault then return end

		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) then
				local name = vim.api.nvim_buf_get_name(buf)
				if name:match("%.md$") and name:find(vim.pesc(cfg.vault), 1, true) then
					local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
					for _, line in ipairs(lines) do
						if line:match("^```dataview%s*$") then
							require("dataview.ui").render_buffer(buf)
							break
						end
					end
				end
			end
		end
	end,
})
