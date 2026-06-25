local M = {}

local DQL_KEYWORDS = {
	TABLE = true, LIST = true, TASK = true,
	FROM = true, WHERE = true, SORT = true,
	LIMIT = true, AND = true, OR = true,
	ASC = true, DESC = true, AS = true, NOT = true,
}

local function tokenize(s)
	local tokens = {}
	local i = 1
	while i <= #s do
		local c = s:sub(i, i)
		if c:match("%s") then
			i = i + 1
		elseif c == '"' then
			local j = s:find('"', i + 1, true)
			if not j then error("Unterminated string at position " .. i) end
			table.insert(tokens, { type = "string", value = s:sub(i + 1, j - 1) })
			i = j + 1
		elseif c == "'" then
			local j = s:find("'", i + 1, true)
			if not j then error("Unterminated string at position " .. i) end
			table.insert(tokens, { type = "string", value = s:sub(i + 1, j - 1) })
			i = j + 1
		elseif c == "#" then
			local j = i + 1
			while j <= #s and s:sub(j, j):match("[%w_%-/]") do j = j + 1 end
			table.insert(tokens, { type = "tag", value = s:sub(i + 1, j - 1) })
			i = j
		elseif s:sub(i, i + 1) == "!=" then
			table.insert(tokens, { type = "op", value = "!=" })
			i = i + 2
		elseif s:sub(i, i + 1) == "<=" then
			table.insert(tokens, { type = "op", value = "<=" })
			i = i + 2
		elseif s:sub(i, i + 1) == ">=" then
			table.insert(tokens, { type = "op", value = ">=" })
			i = i + 2
		elseif c == "=" then
			table.insert(tokens, { type = "op", value = "=" })
			i = i + 1
		elseif c == "<" then
			table.insert(tokens, { type = "op", value = "<" })
			i = i + 1
		elseif c == ">" then
			table.insert(tokens, { type = "op", value = ">" })
			i = i + 1
		elseif c == "," then
			table.insert(tokens, { type = "comma" })
			i = i + 1
		elseif c == "(" then
			table.insert(tokens, { type = "lparen" })
			i = i + 1
		elseif c == ")" then
			table.insert(tokens, { type = "rparen" })
			i = i + 1
		elseif c:match("[%a_]") then
			local j = i
			while j <= #s and s:sub(j, j):match("[%w_%.%-]") do j = j + 1 end
			local word = s:sub(i, j - 1)
			local upper = word:upper()
			if DQL_KEYWORDS[upper] then
				table.insert(tokens, { type = "keyword", value = upper })
			else
				table.insert(tokens, { type = "ident", value = word })
			end
			i = j
		elseif c:match("%d") then
			local j = i
			while j <= #s and s:sub(j, j):match("%d") do j = j + 1 end
			table.insert(tokens, { type = "number", value = tonumber(s:sub(i, j - 1)) })
			i = j
		else
			i = i + 1
		end
	end
	return tokens
end

-- Parser state (module-level, reset per parse call)
local _tokens
local _pos

local function peek()
	return _tokens[_pos]
end

local function advance()
	local t = _tokens[_pos]
	_pos = _pos + 1
	return t
end

local function match_keyword(kw)
	local t = peek()
	if t and t.type == "keyword" and t.value == kw then
		advance()
		return true
	end
	return false
end

local RESERVED_IN_FIELD = {
	FROM = true, WHERE = true, SORT = true,
	LIMIT = true, AND = true, OR = true, AS = true,
}

local function parse_field()
	local t = peek()
	if not t then return nil end
	local is_ident = t.type == "ident"
	local is_non_reserved_kw = t.type == "keyword" and not RESERVED_IN_FIELD[t.value]
	if not (is_ident or is_non_reserved_kw) then return nil end

	advance()
	local field = { name = t.value, alias = nil }
	local n = peek()
	if n and n.type == "keyword" and n.value == "AS" then
		advance()
		local alias_tok = advance()
		if alias_tok then field.alias = alias_tok.value end
	end
	return field
end

local function parse_condition()
	local t = peek()
	if not t then return nil end

	-- function call: fn(arg, arg)
	if t.type == "ident" and _tokens[_pos + 1] and _tokens[_pos + 1].type == "lparen" then
		local fn_name = advance().value
		advance() -- (
		local args = {}
		while peek() and peek().type ~= "rparen" do
			local arg = advance()
			if arg.type ~= "comma" then
				table.insert(args, arg.value ~= nil and tostring(arg.value) or "")
			end
			if peek() and peek().type == "comma" then advance() end
		end
		if peek() and peek().type == "rparen" then advance() end
		return { type = "fn", fn = fn_name, args = args }
	end

	-- field op value
	if t.type == "ident" then
		local field = advance().value
		local op_tok = peek()
		if not op_tok or op_tok.type ~= "op" then
			return { type = "exists", field = field }
		end
		advance() -- consume op
		local val_tok = advance()
		local val = val_tok and val_tok.value or nil
		return { type = "compare", op = op_tok.value, field = field, value = val }
	end

	return nil
end

local function parse_where_expr()
	local left = parse_condition()
	if not left then return nil end

	local n = peek()
	if n and n.type == "keyword" and (n.value == "AND" or n.value == "OR") then
		local op = advance().value
		local right = parse_where_expr()
		return { type = "logical", op = op, left = left, right = right }
	end

	return left
end

function M.parse(dql)
	_tokens = tokenize(dql)
	_pos = 1

	local ast = {
		type   = "LIST",
		fields = {},
		from   = { type = "all" },
		where  = nil,
		sort   = nil,
		limit  = nil,
	}

	local t = peek()
	if not t then return ast end

	if t.type == "keyword" and (t.value == "TABLE" or t.value == "LIST" or t.value == "TASK") then
		ast.type = advance().value
	end

	if ast.type == "TABLE" then
		local field = parse_field()
		while field do
			table.insert(ast.fields, field)
			if peek() and peek().type == "comma" then
				advance()
				field = parse_field()
			else
				break
			end
		end
	elseif ast.type == "LIST" then
		local n = peek()
		if n and n.type == "ident" then
			local field = parse_field()
			if field then table.insert(ast.fields, field) end
		end
	end

	if match_keyword("FROM") then
		local n = peek()
		if n then
			if n.type == "string" then
				advance()
				ast.from = n.value == "" and { type = "all" } or { type = "folder", value = n.value }
			elseif n.type == "tag" then
				advance()
				ast.from = { type = "tag", value = n.value }
			end
		end
	end

	if match_keyword("WHERE") then
		ast.where = parse_where_expr()
	end

	if match_keyword("SORT") then
		local field_tok = advance()
		local dir = "ASC"
		local n = peek()
		if n and n.type == "keyword" and (n.value == "ASC" or n.value == "DESC") then
			dir = advance().value
		end
		ast.sort = { field = field_tok and field_tok.value, dir = dir }
	end

	if match_keyword("LIMIT") then
		local n_tok = advance()
		if n_tok and n_tok.type == "number" then
			ast.limit = n_tok.value
		end
	end

	return ast
end

return M
