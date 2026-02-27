local TypeChecker = {}

---Validates 'value' against 'schema'.
---
---Schema can be:
--- - '"any"' - always passes
--- - a string like '"string"', '"number"', '"boolean"', '"table"' - checks 'type(value)'
--- - a table like '{ key = "string", nested = { x = "number" } }' - recurses into the value
---
---Returns 'true' on success, or 'false, errorMessage' on failure.
---@param value any
---@param schema string | table
---@param path string?
---@return boolean ok
---@return string? err
function TypeChecker.check(value, schema, path)
	path = path or "arg"

	if schema == "any" then
		return true
	end

	if type(schema) == "string" then
		if type(value) ~= schema then
			return false, `[{path}] expected {schema}, got {type(value)}`
		end
		return true
	end

	if type(schema) == "table" then
		if type(value) ~= "table" then
			return false, `[{path}] expected table, got {type(value)}`
		end
		for key, subSchema in pairs(schema) do
			local ok, err = TypeChecker.check(value[key], subSchema, `{path}.{tostring(key)}`)
			if not ok then
				return false, err
			end
		end
		return true
	end

	return false, `[{path}] unknown schema type: {type(schema)}`
end

return TypeChecker
