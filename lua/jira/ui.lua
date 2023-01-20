M = {}

local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local ts_utils = require("telescope.utils")
local defaulter = ts_utils.make_default_callable

local Path = require("plenary.path")
local jira = require("jira")

local status_map = {
	[" "] = { "To Do", "TO DO", "TODO", "To DO", "TO Do" },
	["-"] = { "In Progress", "IN PROGRESS", "INPROGRESS", "In PROGRESS", "IN Progress" },
	["o"] = { "Done", "DONE" },
	["x"] = { "Blocked", "BLOCKED", "WON'T DO", "ABANDONED", "ABANDON" },
}

function table.append(t1, t2)
	for i = 1, #t2 do
		t1[#t1 + 1] = t2[i]
	end
	return t1
end


--- export issue json to markdown
---@param issue table
---@param comments table
---@return table
M.issue_to_markdown = function(issue, comments)
	-- vim.fn.writefile(vim.split(vim.json.encode(issue), '\n'), "tmp_issue.json")

	local lines = {}

	local attribute_lines = M.parse_attributes(issue)
	local desc_lines = M.parse_description(issue)
	local childs_lines = M.parse_childs(issue)
	-- TODO: issue already incudes comments
	local comment_lines = M.parse_comments(comments)

	for _, section_lines in ipairs({ attribute_lines, desc_lines, childs_lines, comment_lines }) do
		for _, line in ipairs(section_lines) do
			table.insert(lines, line)
		end
	end

	return lines
end

--- parse issue attributes
---@param issue table
---@return table
M.parse_attributes = function(issue)
	local parent_key = nil
	if issue.fields.parent then
		parent_key = issue.fields.parent.key
	else
		parent_key = ""
	end

	if type(issue.fields.assignee) == "table" then
		assignee = issue.fields.assignee.displayName
	else
		assignee = ""
	end

	local lines = {
		"<!-- attributes -->",
		"key:" .. issue.key,
		"summary:" .. issue.fields.summary,
		"assignee:" .. assignee,
		"project:" .. issue.fields.project.key,
		"parent:" .. parent_key,
		"status:[" .. M.status_to_icon(issue.fields.status.name) .. "]",
		"sprint:" .. M.parse_issue_sprint(issue),
		"space:" .. string.match(issue.self, "https://(.*)/rest/api/2/issue/.*"),
		"priority:" .. issue.fields.priority.name,
		"",
		"---",
	}
	return lines
end

--- parse issue sprint
---@param issue table
---@return string
M.parse_issue_sprint = function(issue)
	for _, field in pairs(issue["fields"]) do
		if type(field) == "table" then
			if #field > 0 and field[1]["boardId"] ~= nil then
				return field[1]["id"]
			end
		end
	end
	return ""
end

--- status string to icon
---@param status string
---@return string
M.status_to_icon = function(status)
	if status == nil or status == "" then
		status = " "
	end
	for icon, maps in pairs(status_map) do
		for _, map in pairs(maps) do
			if map == status then
				return icon
			end
		end
	end
	return status
end

--- translate status icon to string
---@param icon string
---@param transitions table
---@return string
M.icon_to_status = function(icon, transitions)
	for _, map in pairs(status_map[icon]) do
		if transitions[map] ~= nil then
			return map
		end
	end
	for _, map in pairs(status_map[" "]) do
		if transitions[map] ~= nil then
			return map
		end
	end
	return nil
end

--- parse issue description
---@param issue table
---@return table
M.parse_description = function(issue)
	local lines = { "<!-- description -->" }
	if type(issue.fields.description) ~= "userdata" then
		local mdlines = vim.split(issue.fields.description, "\n")
		for _, mdline in ipairs(mdlines) do
			table.insert(lines, mdline)
		end
	end
	lines[#lines + 1] = "---"
	return lines
end

--- parse issue childs
---@param issue table
---@return table
M.parse_childs = function(issue)
	if issue == nil or issue.fields == nil or issue.fields.subtasks == nil then
		return {}
	end

	local lines = { "<!-- childs -->" }
	if issue.fields.subtasks ~= nil then
		for _, v in ipairs(issue.fields.subtasks) do
			line = string.format("- [%s][%s]/'%s'", M.status_to_icon(v.fields.status.name), v.key, v.fields.summary)
			table.insert(lines, line)
		end
	end
	lines[#lines + 1] = "---"
	return lines
end

--- parse issue comments
---@param comments table
---@return table
M.parse_comments = function(comments)
	if comments == nil then
		return {}
	end

	local lines = { "<!-- comments -->" }

	for _, comment in ipairs(comments) do
		line = string.format("### [ID-%s][%s]: %s", comment.id, comment.author.displayName, comment.created)
		table.insert(lines, line)
		for _, ll in ipairs(vim.split(comment.body, "\n")) do
			table.insert(lines, ll)
		end
	end

	lines[#lines + 1] = "---"
	return lines
end

M.open_float = function(lines)
	local width = vim.api.nvim_get_option("columns")
	local height = vim.api.nvim_get_option("lines")
	local win_height = math.ceil(height * 0.9 - 4)
	local win_width = math.ceil(width * 0.9)
	local row = math.ceil((height - win_height) / 2 - 1)
	local col = math.ceil((width - win_width) / 2)
	local buf = vim.api.nvim_create_buf(true, true)

	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.b[buf].parent_buf = vim.api.nvim_get_current_buf()
	local _ = vim.api.nvim_open_win(buf, true, {
		style = "minimal",
		relative = "editor",
		row = row,
		col = col,
		width = win_width,
		height = win_height,
		border = "rounded",
	})
	vim.w.is_floating_scratch = true

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	return buf
end

local issue_previewer = defaulter(function(opts)
	return previewers.new_buffer_previewer({
		title = "Description",
		get_buffer_by_name = function(_, entry)
			return entry.value
		end,
		define_preview = function(self, entry)
			local bufnr = self.state.bufnr
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, entry.description)
			vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
		end,
	})
end)

M.issues_picker = function(issues)
	local markdown_issues = {}

	for _, issue in ipairs(issues.issues) do
		table.insert(markdown_issues, { key = issue.key, text = M.issue_to_markdown(issue), tmp = "hi" })
	end

	pickers
		.new({}, {
      prompt_title = "Issues picker",
			results_title = "contents",
			finder = finders.new_table({
				results = markdown_issues,
				entry_maker = function(entry)
					return {
						value = entry.key,
						display = entry.key,
						description = entry.text,
						ordinal = entry.key,
					}
				end,
			}),
			previewer = issue_previewer.new({}),
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = actions_state.get_selected_entry()
					actions.close(prompt_bufnr)
					M.open_float(selection.description)
				end)
				return true
			end,
		})
		:find()
	return
end



local fillstr = function(text) 
  return text or ""
end

M.get_issue_template = function(info)

  local attribute_lines = {}
  for _, attribute in ipairs({ 'summary', 'project', 'parent', 'status', 'sprint', 'space', 'priority' }) do

    local line = string.format("%s:%s", attribute, fillstr(info[attribute]))
    table.insert(attribute_lines, line)
  end

  attribute_lines = table.append(attribute_lines, {
    "",
    "---",
    "<!-- description -->",
    "---",
    "<!-- childs -->",
    "---",
  })

	return table.append({
		"<!-- attributes -->",
    "key:",
	}, attribute_lines)

end

-- generate adf table from markdown text
---@param lines 
---@return 
M.make_adf = function(lines)
	if lines[#lines] ~= "" then
		lines[#lines + 1] = " "
	end

	local description = { type = "doc", version = 1, content = {} }
	local bullet_list = { type = "bulletList", content = {} }

	for _, line in ipairs(lines) do
		if string.match(line, "\\") then
			line = string.gsub(line, "\\", "")
		end
		if string.sub(line, 1, 2) == "* " then
			table.insert(bullet_list.content, {
				type = "listItem",
				content = { { type = "paragraph", content = { { type = "text", text = line:sub(3) } } } },
			})
		else
			if #bullet_list.content > 0 then
				table.insert(description.content, bullet_list)
				bullet_list = { type = "bulletList", content = {} }
			end
			if line == "" then
				line = " "
			end
			table.insert(description.content, { type = "paragraph", content = { { type = "text", text = line } } })
		end
	end
	return description
end


--- parse single child line to table
---@param child_line 
---@return 
M.parse_child_line = function(child_line)
	local lines = vim.split(child_line, "/")
	local child_attrs = lines[1]:sub(3)
	local attrs = vim.split(child_attrs, "]")
	local fetched_attrs = {}
	for _, attr in ipairs(attrs) do
		table.insert(fetched_attrs, string.match(attr, "%[(.*)"))
	end
	if #fetched_attrs == 0 or fetched_attrs == nil then
		return nil
	end
	return { key = fetched_attrs[2], status = fetched_attrs[1], summary = lines[2]:sub(2, -2) }
end

--- read buffer and parse. return table that includes body, childs, space 
---@param bufnr 
M.read_issue_buf = function(bufnr)
	bufnr = bufnr or 0
  
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local sections = {}
	local section = {}
	for _, line in ipairs(lines) do
		if string.match(line, "%-%-%-") then
			table.insert(sections, section)
			section = {}
		else
			if string.match(line, "%!%-%-") == nil then
				table.insert(section, line)
			end
		end
	end

	local attributes = {}
	for _, line in ipairs(sections[1]) do
		attr = vim.split(line, ":")
		attributes[attr[1]] = attr[2]
	end

	local childs = {}
	if #sections[3] > 0 then
		for _, line in ipairs(sections[3]) do
			table.insert(childs, M.parse_child_line(line))
		end
	end
  
  -- body that can be used for newly creating issue
	local body = vim.json.encode({
		fields = {
			project = {
				key = attributes["project"],
			},
			summary = attributes["summary"],
			issuetype = {
				name = "Task",
			},
			-- parent = {
			-- 	key = attributes["parent"],
			-- },
			assignee = nil,
			description = table.concat(sections[2], "\n"),
		},
	})
  
	return { attributes = attributes, description = table.concat(sections[2], "\n"), childs = childs, body=body}

end

return M
