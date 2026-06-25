local M = {}

local _config = {
	vault       = nil,
	auto_render = true,
}

local function detect_vault()
	local ok, obs = pcall(require, "obsidian")
	if not ok then return nil end
	local client = obs.get_client and obs.get_client()
	if client and client.dir then
		return vim.fn.expand(tostring(client.dir))
	end
	return nil
end

function M.setup(opts)
	_config = vim.tbl_deep_extend("force", _config, opts or {})

	if not _config.vault then
		_config.vault = detect_vault()
	end

	if _config.vault then
		require("dataview.index").build(_config.vault)
	else
		vim.notify(
			"[dataview] No vault found. Pass vault= to setup() or install obsidian.nvim.",
			vim.log.levels.WARN
		)
	end
end

function M.get_config()
	return _config
end

function M.register_function(name, fn)
	require("dataview.executor").register_function(name, fn)
end

function M.register_renderer(name, fn)
	require("dataview.renderer").register_renderer(name, fn)
end

function M.query(dql_string)
	local ast  = require("dataview.parser").parse(dql_string)
	local rows = require("dataview.executor").run(ast)
	return rows, ast
end

return M
