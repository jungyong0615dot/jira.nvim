local M = {}

local Job = require("plenary.job")
local Path = require("plenary.path")
local curl = require("custom_curl")
local defaults = require("jira.defaults")
local jira = require("jira")
local jui = require("jira.ui")
local r = require("jira.rest")

local function convert_time_format(str, from, to)
	local year, month, day, hour, min, sec, msec, tz = string.match(str, from)
	return string.format(to, year, month, day, hour, min, sec, msec, tz)
end

local function str2time(str, format)
	local year, month, day, hour, min, sec, msec, tz = string.match(str, format)

	local t = os.time({ year = year, month = month, day = day, hour = hour, min = min, sec = sec })
	return t
end

M.open_issue = function(space, issue_id)
	local issue = nil
	local comments = nil

	r.get(space, string.format("issue/%s?expand=renderedFields", issue_id), function(out)
		issue = vim.json.decode(out.body)
		comments = issue.fields.comment.comments
		local lines = jui.issue_to_markdown(issue, comments)

		jui.open_float(lines)
		vim.cmd("w! " .. (Path:new(jira.opts.path_issues) / issue.key .. ".md"))

		vim.notify("Issue " .. issue.key .. " opened")
	end):start()
end

M.query_issues = function(space, query)
	local issues = nil

	r.get(space, string.format("search?jql=%s", query), function(out)
		issues = vim.json.decode(out.body)
		jui.issues_picker(issues)
	end):start()
end

M.create_issue = function(space, body)
	return r.post(space, "issue/", body, function(out)
		local issue = vim.json.decode(out.body)
		vim.notify("Issue " .. issue.key .. " created", "info", { title = "Create done" })
	end)
end

M.delete_issue = function(space, issue_id)
	r.delete(space, string.format("issue/%s", issue_id), function(out)
		if out.status == 204 then
			vim.notify("Issue deleted", "info", { title = "Delete done" })
		else
			vim.notify("Error deleting issue", "error", { title = "Delete error" })
		end
	end):start()
end

--- Update issue with given body
---@param space
---@param issue_id
---@param body
---@param out
M.update_issue = function(space, issue_id, body)
	r.put(space, string.format("issue/%s", issue_id), body, function(out)
		if out.status == 204 then
			vim.notify("Issue updated", "info", { title = "Update done" })
		else
			vim.notify("Error updating issue", "error", { title = "Update error" })
		end
	end):start()
end

--- Transit issue with given issue_id to given status
---@param space
---@param issue_id
---@param target_status: str. Name like "To Do" or icon like "-" defined in ui.status_map
M.transit_issue = function(space, issue_id, target_status)
	local prj = string.match(issue_id, "[^-]+")
	local map_by_prj = vim.json.decode(table.concat(vim.fn.readfile(jira.opts.transits_path), ""))

	local target_icon = nil
	if target_status:len() < 2 then
		target_icon = target_status
	else
		target_icon = jui.status_to_icon(target_status)
	end

	local post_transit = function(id, issue)
		return r.post(
			space,
			string.format("issue/%s/transitions", issue),
			vim.json.encode({
				transition = {
					id = id,
				},
			}),
			function(out)
				if out.status == 204 then
					vim.notify("issue transition success", "info", { title = "Update done" })
				else
					vim.notify("Error in issue transition", "error", { title = "Update error" })
				end
			end
		)
	end

	if map_by_prj[prj] ~= nil then
		-- TODO: make it as an function
		local prj_status = jui.icon_to_status(target_icon, map_by_prj[prj])
		local transition_id = map_by_prj[prj][prj_status]

		return post_transit(transition_id, issue_id)
	else
		return r.get(space, string.format("issue/%s/transitions", issue_id), function(out)
			local response_table = vim.json.decode(out.body)
			local transitions = {}
			for _, v in ipairs(response_table.transitions) do
				transitions[v.name] = v.id
			end
			map_by_prj[prj] = transitions

			vim.fn.writefile(vim.split(vim.json.encode(map_by_prj), "\n"), jira.opts.transits_path)

			local prj_status = jui.icon_to_status(target_icon, map_by_prj[prj])
			local transition_id = map_by_prj[prj][prj_status]
			post_transit(transition_id, issue_id)
		end)
	end
end

M.get_prj_ids = function(space)
	return r.get(space, "project", function(out)
		local prj_map = {}
		local prjs = vim.json.decode(out.body)
		for _, v in ipairs(prjs) do
			prj_map[v.key] = v.id
		end
		vim.fn.writefile(vim.split(vim.json.encode(prj_map), "\n"), jira.opts.prjmap_path)
	end)
end

M.get_issue_types = function(space, project)
	return r.get(space, string.format("issuetype/project?projectId=%s", project), function(out)
		local response_table = vim.json.decode(out.body)
		local issue_types = {}
		for _, v in ipairs(response_table) do
			issue_types[v.name] = v.id
			-- table.insert(issue_types, {}v.name)
		end
		vim.fn.writefile(vim.split(vim.json.encode(issue_types), "\n"), jira.opts.issuetypes_path)
	end)
end

--- Update issue with given issue_id. read content from current buffer
---@param space
---@param issue_id
---@param out
M.update_changed_fields = function(space, issue_id)
	local fields_to_update = { "summary" }

	local remote_issue = nil
	local remote_comments = nil
	local local_comments = nil
	local is_changed = false
	local body = { fields = {} }

	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local local_issue = jui.markdown_to_issue(lines)
	local local_prj_map = vim.json.decode(table.concat(vim.fn.readfile(jira.opts.prjmap_path), ""))
	local local_issue_types = vim.json.decode(table.concat(vim.fn.readfile(jira.opts.issuetypes_path), ""))

	if local_prj_map[local_issue.attributes.project] == nil then
		local job_prj = M.get_prj_ids(space)
	end

	if local_issue_types[local_issue.attributes.project] == nil then
		local job_issuetype = M.get_issue_types(space, local_issue.attributes.project)
	end

	local job_update_all = r.get(space, string.format("issue/%s?expand=renderedFields", issue_id), function(out)
		remote_issue = vim.json.decode(out.body)
		remote_comments = remote_issue.fields.comment.comments

		-- abort update if remote issue is newer
		if
			str2time(remote_issue.fields.updated, "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).(%d+)(%+.-)$")
			> str2time(local_issue.attributes.updated, "(%d+)-(%d+)-(%d+)T(%d+)_(%d+)_(%d+).(%d+)(%+.-)$")
		then
			vim.notify("Remote issue is newer", "error", { title = "Update error" })
			-- TODO: show diff
			is_changed = true
			return
		end

		-- update changed attributes
		for _, field in ipairs(fields_to_update) do
			if local_issue.attributes[field] ~= remote_issue.fields[field] then
				body.fields[field] = local_issue.attributes[field]
				break
			end
		end
    local jobs = {}

		-- update description
		local job_update = nil
		if local_issue.description ~= remote_issue.fields.description then
			body.fields["description"] = local_issue.description

			job_update = r.put(space, string.format("issue/%s", issue_id), vim.json.encode(body), function(out)
				if out.status == 204 then
					vim.notify("Issue updated", "info", { title = "Update done" })
				else
					vim.notify("Error updating issue", "error", { title = "Update error" })
				end
			end)
		end
    table.insert(jobs, job_update)

		-- update status
		local job_transit = nil
		if local_issue.attributes["status"] ~= jui.status_to_icon(remote_issue.fields.status.name) then
			job_transit = M.transit_issue(space, issue_id, local_issue.attributes["status"])
		end
    table.insert(jobs, job_transit)

		-- update childs
		for _, child in ipairs(local_issue.childs) do
			-- create if not exist
			if child.key == nil or child.key == "" then
        print("create subtask")
				local job_subt = M.create_issue(
					space,
					vim.json.encode({
						fields = {
							project = {
								key = local_issue.attributes["project"],
							},
							summary = child.summary,
							issuetype = {
								subtask = true,
								name = local_issue_types[local_issue.attributes.project]["field_subtask"],
							},
							parent = {
								key = local_issue.attributes["key"],
							},
						},
					})
				)
        table.insert(jobs, job_subt)
			end
			-- update if exist
		end

		-- redraw issue after updates
		local job_redraw = r.get(space, string.format("issue/%s?expand=renderedFields", issue_id), function(out)
			local updated_issue = vim.json.decode(out.body)
			local updated_comments = updated_issue.fields.comment.comments
			local newlines = jui.issue_to_markdown(updated_issue, updated_comments)

			vim.notify("Issue " .. updated_issue.key .. " redrawn")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, newlines)
		end)

    table.insert(jobs, job_redraw)

		-- sekect non-nil jobs
		jobs = vim.tbl_filter(function(job)
			return job ~= nil
		end, jobs)

		Job.chain(unpack(jobs))
	end)

	local all_jobs = { job_prj, job_issuetype, job_update_all }

	all_jobs = vim.tbl_filter(function(job)
		return job ~= nil
	end, all_jobs)

	Job.chain(unpack(all_jobs))
end

M.test = function()
	M.open_issue("jungyong0615dot.atlassian.net", "PRD-137")
end

M.test2 = function()
	M.update_changed_fields("jungyong0615dot.atlassian.net", "PRD-137")

	-- local issue_id = "PRD-155"
	-- local status = "In Progress"
	--
	-- M.transit_issue("jungyong0615dot.atlassian.net", issue_id, status):start()
end

-- jui.open_float(jui.get_issue_template(jira.configs.templates[2]))
--

-- local bufnr = bufnr or 0
-- local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
--  local tmp1 = jui.markdown_to_issue(lines)
-- M.create_issue("jungyong0615dot.atlassian.net", tmp1.body)
-- vim.pretty_print(tmp1)
-- M.delete_issue("jungyong0615dot.atlassian.net", 'PRD-41')
--
--
-- M.open_issue('jungyong0615dot.atlassian.net', 'PRD-137')
-- M.update_issue('jungyong0615dot.atlassian.net', 'PRD-155', '{"fields":{"summary":"test"}}')
-- M.update_issue('jungyong0615dot.atlassian.net', 'PRD-155', '{"fields":{"description":"added desc"}}')

-- get_possible_transits("jungyong0615dot.atlassian.net", "PRD-155")
-- M.open_issue("jungyong0615dot.atlassian.net", "PRD-155")
-- M.get_possible_transits("jungyong0615dot.atlassian.net", "PRD-155")

-- local issue_id = "PRD-155"
-- local status = "In Progress"
--
-- M.transit_issue("jungyong0615dot.atlassian.net", issue_id, status)
--
return M
