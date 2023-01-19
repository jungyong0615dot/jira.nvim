M = {}

local Path = require("plenary.path")
local jira = require("jira")

local status_map = {
	[" "] = { "To Do", "TO DO", "TODO", "To DO", "TO Do" },
	["-"] = { "In Progress", "IN PROGRESS", "INPROGRESS", "In PROGRESS", "IN Progress" },
	["o"] = { "Done", "DONE" },
	["x"] = { "Blocked", "BLOCKED", "WON'T DO", "ABANDONED", "ABANDON" },
}

--- export issue json to markdown
---@param issue table
---@param comments table
---@return table
M.issue_to_markdown = function(issue, comments)
	local lines = {}

	local attribute_lines = M.parse_attributes(issue)
	local desc_lines = M.parse_description(issue)
	local childs_lines = M.parse_childs(issue)
	local comment_lines = M.parse_comments(comments)

	for _, section_lines in ipairs({ attribute_lines, desc_lines, childs_lines, comment_lines }) do
		for _, line in ipairs(section_lines) do
			table.insert(lines, line)
		end
	end

	vim.fn.writefile(lines, (Path:new(jira.opts.path_issues) / issue.key .. ".md"))
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

return M
