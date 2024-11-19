local function label_package(label)
	local index = label:find(':')
	if index then
		return label:sub(1, index - 1)
	end
	return label
end

local source = {}

source.new = function() return setmetatable({}, { __index = source }) end

function source:is_available()
	return vim.bo.filetype == "starlark"
end

---@param params cmp.SourceCompletionApiParams
---@param callback fun(response: lsp.CompletionResponse|nil)
function source:complete(params, callback)
	local stdout_pipe = vim.uv.new_pipe()
	local stdout = ""

	vim.uv.spawn("bazel", {
		args = { 'query', '//...', '--output=streamed_jsonproto' },
		stdio = { nil, stdout_pipe, nil },
		hide = true,
	}, function(code, _)
		if code ~= 0 then return end
		--- @type lsp.CompletionResponse
		local items = {}
		local packages = {}
		for _, line in ipairs(vim.split(stdout, '\n', { plain = true, trimempty = true })) do
			local item = vim.json.decode(line)
			if item.type == 'RULE' then
				local package_name = label_package(item.rule.name)
				if not packages[package_name] then
					packages[package_name] = true
				end
				table.insert(items, {
					label = item.rule.name,
					labelDetails = {
						description = item.ruleClass,
					},
				})
			end
		end

		table.insert(items, {
			label = "//visibility:public",
			documentation = {
				kind = "plaintext",
				value = "Grants access to all packages.",
			}
		})

		table.insert(items, {
			label = "//visibility:private",
			documentation = {
				kind = "plaintext",
				value = "Does not grant any additional access; only targets in this package can use this target.",
			}
		})

		for pkg, _ in pairs(packages) do
			table.insert(items, {
				label = pkg .. ":__pkg__",
				documentation = {
					kind = "markdown",
					value = "Grants access to `" .. pkg .. "` (but not its subpackages).",
				}
			})
			table.insert(items, {
				label = pkg .. ":__subpackages__",
				documentation = {
					kind = "markdown",
					value = "Grants access `" .. pkg .. "` and all of its direct and indirect subpackages.",
				}
			})
		end

		callback(items)
	end)

	vim.uv.read_start(stdout_pipe, function(err, data)
		if data ~= nil then
			stdout = stdout .. data
		end
	end)
end

return source;
