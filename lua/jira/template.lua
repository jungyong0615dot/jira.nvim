M = {}

local status_map = {
	[" "] = { "To Do", "TO DO", "TODO", "To DO", "TO Do" },
	["-"] = { "In Progress", "IN PROGRESS", "INPROGRESS", "In PROGRESS", "IN Progress" },
	["o"] = { "Done", "DONE" },
	["x"] = { "Blocked", "BLOCKED", "WON'T DO", "ABANDONED", "ABANDON" },
}

M.issue_to_markdown = function(issue, comments)
	local lines = {}

	local attribute_lines = M.parse_attributes(issue)
	local desc_lines = M.parse_description(issue)
	local childs_lines = M.parse_childs(issue)
	local comment_lines = M.parse_comments(comments)

  for _, section_lines in ipairs({attribute_lines, desc_lines, childs_lines, comment_lines}) do
    for _, line in ipairs(section_lines) do
      table.insert(lines, line)
    end
  end

	vim.fn.writefile(lines, M.opts.path_issues .. issue.key .. ".md")
	return lines
end


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
		"---",
	}
	return lines
end

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

return M
