local M = {}

local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local ts_utils = require("telescope.utils")
local defaulter = ts_utils.make_default_callable

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
		vim.b.jira_issue = issue_id
		vim.t.jira_space = space

		vim.cmd("w! " .. (Path:new(jira.opts.path_issues) / issue.key .. ".md"))

		vim.notify("Issue " .. issue.key .. " opened")
	end):start()
end

M.query_issues = function(space, query)
	local issues = nil

	return r.get(space, string.format("search?jql=%s", query), function(out)
		issues = vim.json.decode(out.body)
		jui.issue_table(issues)
		vim.t.jira_space = space
		vim.t.jira_query = query
	end)
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
	end)
end

--- Update issue with given body
---@param space
---@param issue_id
---@param body
---@param out
M.update_issue = function(space, issue_id, body)
	return r.put(space, string.format("issue/%s", issue_id), body, function(out)
		if out.status == 204 then
			vim.notify("Issue updated", "info", { title = "Update done" })
		else
			vim.notify("Error updating issue", "error", { title = "Update error" })
		end
	end)
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
	local prjs = vim.json.decode(table.concat(vim.fn.readfile(jira.opts.prjmap_path), ""))

	return r.get(space, string.format("issuetype/project?projectId=%s", prjs[project]), function(out)
		local response_table = vim.json.decode(out.body)
		local exiting = vim.json.decode(table.concat(vim.fn.readfile(jira.opts.issuetypes_path), ""))

		local issue_types = {}
		for _, v in ipairs(response_table) do
			-- issue_types[v.name] = v.id
			if v.subtask then
				issue_types["field_subtask"] = v.name
			elseif string.lower(v.name) == "epic" then
				issue_types["field_epic"] = v.name
			elseif string.lower(v.name) == "task" then
				issue_types["field_task"] = v.name
			end
		end
		exiting[project] = issue_types
		vim.fn.writefile(vim.split(vim.json.encode(exiting), "\n"), jira.opts.issuetypes_path)
	end)
end

--- Update issue with given issue_id. read content from current buffer
---@param space
---@param issue_id
---@param out
M.update_changed_fields = function(space, issue_id)
	local fields_to_update = { "summary", "priority" }

	local all_jobs = {}
	local remote_issue = nil
	local remote_comments = nil
	local local_comments = nil
	local is_changed = false
	local body = { fields = {} }

	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local local_issue = jui.markdown_to_issue(lines)

	if issue_id == "UNDEFINED" then
		table.insert(
			all_jobs,
			M.create_issue(
				space,
				vim.json.encode({
					fields = {
						project = {
							key = local_issue.attributes["project"],
						},
						summary = local_issue.attributes["summary"],
						assignee = {},
						issuetype = {
							name = "Task",
						},
						description = local_issue.description,
						parent = {
							key = local_issue.attributes["parent"],
						},
					},
				})
			)
		)

		if vim.t.jira_query ~= nil then
			table.insert(all_jobs, M.query_issues(space, vim.t.jira_query))
		end

		Job.chain(unpack(vim.tbl_filter(function(job)
			return job ~= nil
		end, all_jobs)))
		return
	end

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
			str2time(remote_issue.fields.updated, "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).(%d+)")
			> str2time(local_issue.attributes.updated, "(%d+)-(%d+)-(%d+)T(%d+)_(%d+)_(%d+).(%d+)")
		then
			vim.notify("Remote issue is newer", "error", { title = "Update error" })
			-- TODO: show diff
			is_changed = true
			return
		end

		local is_updated = false
		-- update changed attributes
		-- for _, field in ipairs(fields_to_update) do
		if local_issue.attributes["summary"] ~= remote_issue.fields["summary"] then
			body.fields["summary"] = local_issue.attributes["summary"]
			is_updated = true
		end

		if local_issue.attributes["priority"] ~= remote_issue.fields.priority["name"] then
			body.fields["priority"] = { name = local_issue.attributes["priority"] }
			is_updated = true
		end

		-- end
		local jobs = {}

		-- update description
		local job_update = nil
		if local_issue.description ~= remote_issue.fields.description then
			body.fields["description"] = local_issue.description
			is_updated = true
		end

		if is_updated then
			job_update = r.put(space, string.format("issue/%s", issue_id), vim.json.encode(body), function(out)
				if out.status == 204 then
					vim.notify("Issue updated", "info", { title = "Update done" })
				else
					vim.notify("Error updating issue", "error", { title = "Update error" })
					vim.pretty_print(out)
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

		local local_issue_types = vim.json.decode(table.concat(vim.fn.readfile(jira.opts.issuetypes_path), ""))

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
							assignee = {},
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
			elseif remote_issue.fields.subtasks ~= nil then
				for _, v in ipairs(remote_issue.fields.subtasks) do
					if child.key == v.key then
						-- update if exist and changed
						if child.summary ~= v.fields.summary then
							local job_subt = M.update_issue(
								space,
								v.key,
								vim.json.encode({
									fields = {
										summary = child.summary,
									},
								})
							)
							vim.pretty_print("job summary")
							table.insert(jobs, job_subt)
						end
						-- trsnsit if status changed
						if child.status ~= jui.status_to_icon(v.fields.status.name) then
							local job_subt = M.transit_issue(space, v.key, child.status)
							table.insert(jobs, job_subt)
						end
					end
				end
			end
		end

		-- redraw issue after updates
		local job_redraw = r.get(space, string.format("issue/%s?expand=renderedFields", issue_id), function(out)
			local updated_issue = vim.json.decode(out.body)
			local updated_comments = updated_issue.fields.comment.comments
			local newlines = jui.issue_to_markdown(updated_issue, updated_comments)

			vim.notify("Issue " .. updated_issue.key .. " redrawn")
			vim.api.nvim_buf_set_lines(0, 0, -1, false, newlines)
			if vim.t.jira_query ~= nil then
				M.query_issues(space, vim.t.jira_query):start()
			end
		end)

		table.insert(jobs, job_redraw)

		-- select non-nil jobs
		jobs = vim.tbl_filter(function(job)
			return job ~= nil
		end, jobs)

		Job.chain(unpack(jobs))
	end)

	all_jobs = { job_prj, job_issuetype, job_update_all }

	all_jobs = vim.tbl_filter(function(job)
		return job ~= nil
	end, all_jobs)

	Job.chain(unpack(all_jobs))
end

M.open_issue_in_table = function()
	local tline = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = tline[cursor[1]]
	local issue_id = vim.split(line, "║")[2]
	-- trim whitespace
	issue_id = string.gsub(issue_id, "^%s*(.-)%s*$", "%1")
	M.open_issue(vim.t.jira_space, issue_id)
end

M.pick_jql = function()
	local config = vim.json.decode(table.concat(vim.fn.readfile(jira.opts.config_path), ""))

	pickers
		.new({}, {
			prompt_title = "Predefined JQL filters",
			results_title = "JQL",
			finder = finders.new_table({
				results = config["filters"],
				entry_maker = function(entry)
					return {
						value = entry.display,
						display = entry.display,
						ordinal = entry.display,
						jql = entry.jql,
						space = entry.space,
					}
				end,
			}),
			sorter = conf.file_sorter({}),
			default_selection_index = 1,
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = actions_state.get_selected_entry()
					actions.close(prompt_bufnr)
					M.query_issues(selection.space, r.encodeURI(selection.jql)):start()
				end)
				return true
			end,
		})
		:find()
end

M.create_issue_from_template = function()
	local config = vim.json.decode(table.concat(vim.fn.readfile(jira.opts.config_path), ""))

	pickers
		.new({}, {
			prompt_title = "Predefined task template",
			results_title = "templates",
			finder = finders.new_table({
				results = config["templates"],
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry.display,
						ordinal = entry.display,
					}
				end,
			}),
			sorter = conf.file_sorter({}),
			default_selection_index = 1,
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = actions_state.get_selected_entry()
					actions.close(prompt_bufnr)
					M.open_task_template(selection.value)
				end)
				return true
			end,
		})
		:find()

	return results
end

M.open_task_template = function(entry)
	prefix = entry["summary"] or ""
	project = entry["project"] or ""
	parent = entry["parent"] or ""
	status = entry["status"] or ""
	sprint = entry["sprint"] or ""
	space = entry["space"] or ""
	priority = entry["priority"] or ""

	lines = {
		"<!-- attributes -->",
		"key:",
		"summary:" .. prefix .. " ",
		"project:" .. project,
		"parent:" .. parent,
		"status:" .. status,
		"sprint:" .. sprint,
		"space:" .. space,
		"priority:" .. priority,
		"updated:" .. os.date("%Y-%m-%d"),
		"---",
		"<!-- description -->",
		"* issue description",
		"---",
		"<!-- childs -->",
		"---",
	}
	vim.cmd("enew")
	vim.b.jira_issue = "UNDEFINED"
	vim.t.jira_space = space

	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

M.test = function()
	-- vim.fn.writefile(vim.split(vim.json.encode({["PRD-2000"]={rank=10}}), "\n"), jira.opts.metadata_path)
	-- vim.pretty_print(vim.json.decode(table.concat(vim.fn.readfile(jira.opts.metadata_path), "")))
	-- jui.
  M.open_issue("jungyong0615dot.atlassian.net", "PRD-81")
end

M.test2 = function()
  jui.change_issue_order("up")
	-- M.create_issue_from_template()
	-- M.open_issue_in_table()
end

return M
