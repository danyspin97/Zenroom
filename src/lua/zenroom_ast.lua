--[[
--This file is part of zenroom
--
--Copyright (C) 2018-2021 Dyne.org foundation
--designed, written and maintained by Denis Roio <jaromil@dyne.org>
--
--This program is free software: you can redistribute it and/or modify
--it under the terms of the GNU Affero General Public License v3.0
--
--This program is distributed in the hope that it will be useful,
--but WITHOUT ANY WARRANTY; without even the implied warranty of
--MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--GNU Affero General Public License for more details.
--
--Along with this program you should have received a copy of the
--GNU Affero General Public License v3.0
--If not, see http://www.gnu.org/licenses/agpl.txt
--
--Last modified by Denis Roio
--on Tuesday, 6th April 2021
--]]

function zencode_iscomment(b)
	local x = string.char(b:byte(1))
	if x == '#' then
		return true
	else
		return false
	end
end
function zencode_isempty(b)
	if b == nil or trim(b) == '' then
		return true
	else
		return false
	end
end
-- returns an iterator for newline termination
function zencode_newline_iter(text)
	s = trim(text) -- implemented in zen_io.c
	if s:sub(-1) ~= '\n' then
		s = s .. '\n'
	end
	return s:gmatch('(.-)\n') -- iterators return functions
end

function set_sentence(self, event, from, to, ctx)
	local reg = ctx.Z[self.current .. '_steps']
	ctx.Z.OK = false
	xxx('Zencode AST from: ' .. from .. " to: "..to)
	ZEN.assert(
		reg,
		'Steps register not found: ' .. self.current .. '_steps'
	)
	-- TODO: optimize in C
	-- remove '' contents, lower everything, expunge prefixes
	-- ignore 'the' only in Then statements
	local tt = string.gsub(trim(ctx.msg), "'(.-)'", "''")
	if to == 'then' then
		tt = string.gsub(tt, ' the ', ' ', 1)
	end
	tt = string.gsub(tt, ' +', ' ') -- eliminate multiple internal spaces
	tt = string.gsub(tt, 'I ', '', 1)
	tt = string.gsub(tt:lower(), 'when ', '', 1)
	tt = string.gsub(tt, 'then ', '', 1)
	tt = string.gsub(tt, 'given ', '', 1)
	tt = string.gsub(tt, 'and ', '', 1) -- TODO: expunge only first 'and'
	tt = string.gsub(tt, 'that ', '', 1)
	tt = string.gsub(tt, 'valid ', '', 1) -- backward compat
	tt = string.gsub(tt, 'known as ', '', 1)
	tt = string.gsub(tt, 'all ', '', 1)
	tt = string.gsub(tt, ' inside ', ' in ', 1) -- equivalence
	tt = string.gsub(tt, ' an ', ' a ', 1)

	for pattern, func in pairs(reg) do
		if (type(func) ~= 'function') then
			error('Zencode function missing: ' .. pattern, 2)
			return false
		end
		if strcasecmp(tt, pattern) then
			local args = {} -- handle multiple arguments in same string
			for arg in string.gmatch(ctx.msg, "'(.-)'") do
				-- convert all spaces to underscore in argument strings
				arg = uscore(arg, ' ', '_')
				table.insert(args, arg)
			end
			ctx.Z.id = ctx.Z.id + 1
			-- AST data prototype
			table.insert(
				ctx.Z.AST,
				{
					id = ctx.Z.id, -- ordered number
					args = args, -- array of vars
					source = ctx.msg, -- source text
					section = self.current,
					hook = func
				}
			) -- function
			ctx.Z.OK = true
			break
		end
	end
	if not ctx.Z.OK and CONF.parser.strict_match then
		debug_traceback()
		exitcode(1)
		error('Zencode pattern not found: ' .. trim(ctx.msg), 1)
		return false
	elseif not ctx.Z.OK and not CONF.parser.strict_match then
		warn('Zencode pattern ignored: ' .. trim(ctx.msg), 1)
	end
end

function set_rule(text)
	local res = false
	local tr = text.msg:gsub(' +', ' ') -- eliminate multiple internal spaces
	local rule = strtok(trim(tr):lower())
	if rule[2] == 'check' and rule[3] == 'version' and rule[4] then
		-- TODO: check version of running VM
		-- elseif rule[2] == 'load' and rule[3] then
		--     act("zencode extension: "..rule[3])
		--     require("zencode_"..rule[3])
		SEMVER = require_once('semver')
		local ver = SEMVER(rule[4])
		if ver == ZENROOM_VERSION then
			act('Zencode version match: ' .. ZENROOM_VERSION.original)
			res = true
		elseif ver < ZENROOM_VERSION then
			warn('Zencode written for an older version: ' .. ver.original)
			res = true
		elseif ver > ZENROOM_VERSION then
			warn('Zencode written for a newer version: ' .. ver.original)
			res = true
		else
			error('Version check error: ' .. rule[4])
		end
		text.Z.checks.version = res
	elseif rule[2] == 'input' and rule[3] then
		-- rule input encoding|format ''
		if rule[3] == 'encoding' and rule[4] then
			CONF.input.encoding = input_encoding(rule[4])
			res = true and CONF.input.encoding
		elseif rule[3] == 'format' and rule[4] then
			CONF.input.format = get_format(rule[4])
			res = true and CONF.input.format
		elseif rule[3] == 'untagged' then
			res = true
			CONF.input.tagged = false
		end
	elseif rule[2] == 'output' and rule[3] then
		-- TODO: rule debug [ format | encoding ]
		-- rule input encoding|format ''
		if rule[3] == 'encoding' then
			CONF.output.encoding = output_encoding(rule[4])
			res = true and CONF.output.encoding
		elseif rule[3] == 'format' then
			CONF.output.format = get_format(rule[4])
			res = true and CONF.output.format
		elseif rule[3] == 'versioning' then
			CONF.output.versioning = true
			res = true
		elseif strcasecmp(rule[3], 'ast') then
			CONF.output.AST = true
			res = true
		end
	elseif rule[2] == 'unknown' and rule[3] then
		if rule[3] == 'ignore' then
			CONF.parser.strict_match = false
			res = true
		end
	elseif rule[2] == 'set' and rule[4] then
		CONF[rule[3]] = tonumber(rule[4]) or rule[4]
		res = true and CONF[rule[3]]
	end
	if not res then
		error('Rule invalid: ' .. text.msg, 3)
	else
		act(text.msg)
	end
	return res
end

return zencode_parse
