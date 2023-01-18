local M = {}

local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local ts_utils = require("telescope.utils")
local defaulter = ts_utils.make_default_callable

local curl = require("custom_curl")

local transitions = {}


-- TODO: fetch subtaks names
local subtask_map = {
	IN = "하위 작업",
	JPT = "Sub-Task",
	PRD = "Sub-task",
}

function table.append(t1, t2)
	for i = 1, #t2 do
		t1[#t1 + 1] = t2[i]
	end
	return t1
end

M.chain_jobs = function(jobs)
	for index = 2, #jobs do
		local prev_job = jobs[index - 1]
		local job = jobs[index]

		prev_job:add_on_exit_callback(vim.schedule_wrap(function()
			job:start()
		end))
	end

	local last_on_exit = jobs[#jobs]._user_on_exit
	jobs[#jobs]._user_on_exit = function(self, err, data)
		if last_on_exit then
			last_on_exit(self, err, data)
		end
	end

	jobs[1]:start()
end

local function get_auth(space)
	return "Bearer " .. string.format("%s:%s", M.configs.spaces[space]["email"], M.configs.spaces[space]["token"])
end

local function http_get(url_info)
	local headers = {
		authorization = "Basic " .. mime.b64(
			string.format(
				"%s:%s",
				M.configs.spaces[url_info["space"]]["email"],
				M.configs.spaces[url_info["space"]]["token"]
			)
		),
	}
	local response_table = {}
	response, response_code, c, h = http.request({
		url = url_info["url"],
		headers = headers,
		sink = ltn12.sink.table(response_table),
	})

	return table.concat(response_table), response_code
end

local function http_put(url_info, body)
	local headers = {
		authorization = "Basic " .. mime.b64(
			string.format(
				"%s:%s",
				M.configs.spaces[url_info["space"]]["email"],
				M.configs.spaces[url_info["space"]]["token"]
			)
		),
		["Content-Type"] = "application/json",
		["Content-Length"] = body:len(),
	}
	local response_table = {}
	response, response_code, c, h = http.request({
		url = url_info["url"],
		method = "PUT",
		headers = headers,
		sink = ltn12.sink.table(response_table),
		source = ltn12.source.string(body),
	})
	return table.concat(response_table), response_code
end

local function http_post(url_info, body)
	local headers = {
		authorization = "Basic " .. mime.b64(
			string.format(
				"%s:%s",
				M.configs.spaces[url_info["space"]]["email"],
				M.configs.spaces[url_info["space"]]["token"]
			)
		),
		["Content-Type"] = "application/json",
		["Content-Length"] = body:len(),
	}
	local response_table = {}

	response, response_code, c, h = http.request({
		url = url_info["url"],
		method = "POST",
		headers = headers,
		sink = ltn12.sink.table(response_table),
		source = ltn12.source.string(body),
	})
	return table.concat(response_table), response_code
end

math.randomseed(os.clock())
local function randomString(length)
	-- generate random string with specified length. it's used for tmp buffer, cell id generation.
	local charset = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890"
	local ret = {}
	local r
	for _ = 1, length do
		r = math.random(1, #charset)
		table.insert(ret, charset:sub(r, r))
	end
	return table.concat(ret)
end

--- Get single issue
---@param issue_info table {space, issue_id}
---@return table
M.get_issue = function(space, issue_id)
  local url = string.format("https://%s/rest/api/2/issue/%s?expand=renderedFields", space, issue_id)

	curl.get(url, {
		headers = {
			authorization = get_auth(space),
		},
		callback = vim.schedule_wrap(function(out)
			local response_table = vim.json.decode(out.body)
      vim.pretty_print(response_table)
		end),
	}):start()

	return response_table
end

M.get_and_open_issue = function(issue_info, bufnr)
	url = "https://"
		.. issue_info["space"]
		.. "/rest/api/2/issue/"
		.. issue_info["issue_id"]
		.. "?expand=renderedFields"

	local response = nil

	local get_job = curl.get(url, {
		headers = {
			authorization = "Basic " .. mime.b64(
				string.format(
					"%s:%s",
					M.configs.spaces[issue_info["space"]]["email"],
					M.configs.spaces[issue_info["space"]]["token"]
				)
			),
		},
		callback = vim.schedule_wrap(function(out)
			response = vim.json.decode(out.body)

			if bufnr ~= nil and vim.api.nvim_get_current_buf() == bufnr then
				M.open_issue(response)
			end

			require("notify")("Issue update done", "info", { { title = "Update done" } })
		end),
	})
	return get_job
end

--- get multiple issues from jira
---@param url_info table {url, space}
---@return table
M.get_issues = function(url_info)
	response, response_code = http_get(url_info)
	local response_table = vim.json.decode(response)
	return response_table.issues
end

M.get_multiple_issues = function(issues_info)
	keys = table.concat(issues_info["issue_ids"], ",%20")
	url = "https://"
		.. issues_info["space"]
		.. "/rest/api/2/search?fields=description,summary,project,status&expand=renderedFields&jql=key%20in%20("
		.. keys
		.. ")"
	response, response_code = http_get({ url = url, space = issues_info["space"] })
	local response_table = vim.json.decode(response)
	return response_table
end

M.get_epic = function(epics_info, cb)
	local keys = table.concat(epics_info["epic_ids"], ",%20")
	local url = "https://"
		.. epics_info["space"]
		.. "/rest/api/2/search?fields=parent,description,summary,project,issuetype,priority,status,subtasks&expand=renderedFields&jql="
		.. "parent%20IN%20("
		.. keys
		.. ")"

	local get_job = curl.get(url, {
		headers = {
			authorization = "Basic " .. mime.b64(
				string.format(
					"%s:%s",
					M.configs.spaces[epics_info["space"]]["email"],
					M.configs.spaces[epics_info["space"]]["token"]
				)
			),
		},
		callback = vim.schedule_wrap(cb),
	})
	return get_job
end

M.set_issue = function(issue_info, key, value)
	local url = "https://" .. issue_info["space"] .. "/rest/api/2/issue/" .. issue_info["issue_id"]
	local body = {
		fields = {
			[key] = value,
		},
	}
	response, response_code = http_put({ url = url, space = issue_info["space"] }, vim.json.encode(body))
	return response, response_code
end

M.set_issue_job = function(issue_info, key, value)
	local body = vim.json.encode({
		fields = {
			[key] = value,
		},
	})
	local set_job = curl.put("https://" .. issue_info["space"] .. "/rest/api/2/issue/" .. issue_info["issue_id"], {
		headers = {
			authorization = "Basic " .. mime.b64(
				string.format(
					"%s:%s",
					M.configs.spaces[issue_info["space"]]["email"],
					M.configs.spaces[issue_info["space"]]["token"]
				)
			),
			["Content-Type"] = "application/json",
			["Content-Length"] = body:len(),
		},
		body = body,
		callback = function(out) end,
	})
	return set_job
end

M.make_adf = function(lines)
	-- generate adf table from markdown text
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

local description_previewer = defaulter(function(opts)
	return previewers.new_buffer_previewer({
		title = "Description",
		get_buffer_by_name = function(_, entry)
			return entry.value
		end,
		define_preview = function(self, entry)
			local bufnr = self.state.bufnr
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(entry.description, "\n"))
			vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
		end,
	})
end)

M.telescope_issues = function(issues)
	local results = {}

	for _, issue in ipairs(issues) do
		local description = nil
		if type(issue.fields.description) == "userdata" then
			description = "No description"
		else
			description = issue.fields.description
		end

		table.insert(results, {
			value = issue.key,
			display = issue.key .. "|" .. issue.fields.priority.name .. "|" .. issue.fields.summary,
			description = description,
			ordinal = issue.key,
			issue = issue,
		})
	end

	pickers
		.new({}, {
			prompt_title = "Issues",
			results_title = "issue",
			finder = finders.new_table({
				results = results,
				entry_maker = function(entry)
					return {
						value = entry.key,
						display = entry.display,
						description = entry.description,
						ordinal = entry.ordinal,
						issue = entry.issue,
					}
				end,
			}),
			previewer = description_previewer.new({}),
			default_selection_index = 1,
			attach_mappings = function(prompt_bufnr)
				actions.select_default:replace(function()
					local selection = actions_state.get_selected_entry()
					actions.close(prompt_bufnr)
					print("You picked:", selection.display)
					M.open_issue(selection.issue)
				end)
				return true
			end,
		})
		:find()

	return results
end

M.telescope_filters = function()
	local results = M.configs.filters

	for _, result in ipairs(results) do
		result["url"] = "https://"
			.. result["space"]
			.. "/rest/api/2/search?jql="
			.. result["jql"]
			.. "&expand=renderedFields"
	end

	pickers
		.new({}, {
			prompt_title = "Predefined JQL filters",
			results_title = "JQL",
			finder = finders.new_table({
				results = results,
				entry_maker = function(entry)
					return {
						value = entry.url,
						display = entry.display,
						url = entry.url,
						ordinal = entry.display,
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
					print("You picked:", selection.display)
					M.telescope_issues(M.get_issues({ url = selection.url, space = selection.space }))
					print(selection.url)
				end)
				return true
			end,
		})
		:find()

	return results
end

M.get_section_attributes = function(issue)
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

	if assignee == M.configs.name then
		assignee = "Me"
	end

	local lines = {
		"<!-- attributes -->",
		"key:" .. issue.key,
		"summary:" .. issue.fields.summary,
		"assignee:" .. assignee,
		"project:" .. issue.fields.project.key,
		"parent:" .. parent_key,
		"status:[" .. M.status_to_icon(issue.fields.status.name) .. "]",
		"sprint:" .. M.get_issue_sprint(issue),
		"space:" .. string.match(issue.self, "https://(.*)/rest/api/2/issue/.*"),
		"priority:" .. issue.fields.priority.name,
		"---",
	}
	return lines
end

M.get_section_description = function(issue)
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

M.get_section_childs = function(issue)
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

M.get_section_comments = function(comments)
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

M.issue_to_md = function(issue)
	local lines = {}
	local attribute_lines = M.get_section_attributes(issue)
	local desc_lines = M.get_section_description(issue)
	local childs_lines = M.get_section_childs(issue)

	local comments =
		M.get_comment({ issue_id = issue.key, space = string.match(issue.self, "https://(.*)/rest/api/2/issue/.*") })
	local comment_lines = M.get_section_comments(comments)

	for _, line in ipairs(attribute_lines) do
		table.insert(lines, line)
	end
	for _, line in ipairs(desc_lines) do
		table.insert(lines, line)
	end
	for _, line in ipairs(childs_lines) do
		table.insert(lines, line)
	end

	for _, line in ipairs(comment_lines) do
		table.insert(lines, line)
	end

	vim.fn.writefile(lines, M.opts.path_issues .. issue.key .. ".md")
	return lines
end

M.open_issue = function(space, issue_id)

  local issue = nil
  local comments = nil

	job_content = curl.get(string.format("https://%s/rest/api/2/issue/%s?expand=renderedFields", space, issue_id), {
		auth = string.format("%s:%s", M.configs.spaces[space]["email"], M.configs.spaces[space]["token"]),
		accept = "application/json",
		callback = vim.schedule_wrap(function(out)
			issue = vim.json.decode(out.body)
		end),
	})

  job_comments = curl.get(string.format("https://%s/rest/api/2/issue/%s/comment", space, issue_id), {
    auth = string.format("%s:%s", M.configs.spaces[space]["email"], M.configs.spaces[space]["token"]),
    accept = "application/json",
    callback = vim.schedule_wrap(function(out)
      comments = vim.json.decode(out.body)
    end),
  })

  Job.chain(job_content, job_comments):start()


	-- M.issue_to_md(issue)
	-- vim.cmd("edit " .. M.opts.path_issues .. issue.key .. ".md")
	-- local bufnr = vim.fn.bufnr(M.opts.path_issues .. issue.key .. ".md")
	-- local subtasks = {}
	-- if issue.fields.subtasks ~= nil then
	-- 	for _, subtask in ipairs(issue.fields.subtasks) do
	-- 		table.insert(subtasks, {
	-- 			key = subtask.key,
	-- 			summary = subtask.fields.summary,
	-- 			status = subtask.fields.status.name,
	-- 			description = subtask.fields,
	-- 		})
	-- 	end
	-- end
	-- vim.b[bufnr].subtasks = subtasks
	-- vim.b[bufnr].key = issue.key
	-- vim.b[bufnr].space = string.match(issue.self, "https://(.*)/rest/api/2/issue/.*")
	--
	-- if issue.fields.parent then
	-- 	parent_key = issue.fields.parent.key
	-- else
	-- 	parent_key = ""
	-- end
	--
	-- vim.b[bufnr].attributes = {
	-- 	key = issue.key,
	-- 	summary = issue.fields.summary,
	-- 	project = issue.fields.project.key,
	-- 	parent = parent_key,
	-- 	status = issue.fields.status.name,
	-- 	sprint = M.get_issue_sprint(issue),
	-- 	space = string.match(issue.self, "https://(.*)/rest/api/2/issue/.*"),
	-- 	priority = issue.fields.priority.name,
	-- }
end

M.reload_issue = function(bufnr)
	bufnr = bufnr or 0
	local attributes = M.get_sections(bufnr)
	local key = attributes["attributes"]["key"]
	local space = attributes["attributes"]["space"]

	local issue = M.get_issue({ issue_id = key, space = space })
	M.open_issue(issue)
	print("Reloaded")
end

M.fetch_child_info = function(child_line)
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

M.create_child = function(info)
	local url = "https://" .. info["space"] .. "/rest/api/3/issue/"
	local project = vim.split(info["parent"], "-")[1]
	local body = {
		fields = {
			project = {
				key = project,
			},
			summary = info["summary"],
			issuetype = {
				subtask = true,
				name = subtask_map[project],
			},
			parent = {
				key = info["parent"],
			},
			assignee = {},
		},
	}
	response, response_code = http_post({ url = url, space = info["space"] }, vim.json.encode(body))
	return response
end

M.create_child_job = function(info)
	local project = vim.split(info["parent"], "-")[1]
	local body = vim.json.encode({
		fields = {
			project = {
				key = project,
			},
			summary = info["summary"],
			issuetype = {
				subtask = true,
				name = subtask_map[project],
			},
			parent = {
				key = info["parent"],
			},
			assignee = {},
		},
	})

	local put_job = curl.post("https://" .. info["space"] .. "/rest/api/3/issue/", {
		headers = {
			authorization = "Basic " .. mime.b64(
				string.format(
					"%s:%s",
					M.configs.spaces[info["space"]]["email"],
					M.configs.spaces[info["space"]]["token"]
				)
			),
			["Content-Type"] = "application/json",
			["Content-Length"] = body:len(),
		},
		body = body,
		callback = function(out) end,
	})
	return put_job
end

M.get_possibile_transitions = function(issue_info)
	url = "https://" .. issue_info["space"] .. "/rest/api/3/issue/" .. issue_info["issue_id"] .. "/transitions"
	response, response_code = http_get({ url = url, space = issue_info["space"] })
	local response_table = vim.json.decode(response)
	local transitions = {}
	for _, v in ipairs(response_table.transitions) do
		transitions[v.name] = v.id
	end
	return transitions
end

M.transit_issue = function(info)
	url = "https://" .. info["space"] .. "/rest/api/3/issue/" .. info["key"] .. "/transitions"
	body = {
		transition = {
			id = info["transition"],
		},
	}
	response, response_code = http_post({ url = url, space = info["space"] }, vim.json.encode(body))
	return response, response_code
end

M.transit_issue_job = function(info)
	local body = vim.json.encode({
		transition = {
			id = info["transition"],
		},
	})
	local put_job = curl.post("https://" .. info["space"] .. "/rest/api/3/issue/" .. info["key"] .. "/transitions", {
		headers = {
			authorization = "Basic " .. mime.b64(
				string.format(
					"%s:%s",
					M.configs.spaces[info["space"]]["email"],
					M.configs.spaces[info["space"]]["token"]
				)
			),
			["Content-Type"] = "application/json",
			["Content-Length"] = body:len(),
		},
		body = body,
		callback = function(out) end,
	})
	return put_job
end

local function has_key(issues, key)
	for _, issue in pairs(issues) do
		if issue.key == key then
			return issue
		end
	end
	return nil
end

M.update_attributes = function(attributes, new_attributes)
	local jobs = {}
	for k, v in pairs(new_attributes) do
		if attributes[k] ~= v then
			if k == "status" then
				if transitions[attributes["key"]] == nil then
					transitions[attributes["key"]] =
						M.get_possibile_transitions({ issue_id = attributes["key"], space = new_attributes["space"] })
				end
				target_status =
					M.icon_to_status(string.match(new_attributes["status"], "%[(.*)%]"), transitions[attributes["key"]])
				table.insert(
					jobs,
					M.transit_issue_job({
						status = target_status,
						key = attributes["key"],
						transition = transitions[attributes["key"]][target_status],
						space = attributes["space"],
					})
				)
			elseif k == "sprint" then
				table.insert(
					jobs,
					M.move_issue_to_sprint_job({ issue_id = attributes["key"], space = attributes["space"] }, v)
				)
			elseif k == "priority" then
				table.insert(
					jobs,
					M.set_issue_job(
						{ issue_id = attributes["key"], space = attributes["space"] },
						"priority",
						{ name = v }
					)
				)
			elseif k == "assignee" then
				if v == "" then
					table.insert(
						jobs,
						M.set_issue_job({ issue_id = attributes["key"], space = attributes["space"] }, "assignee", nil)
					)
				elseif v == "Me" then
					table.insert(
						jobs,
						M.set_issue_job(
							{ issue_id = attributes["key"], space = attributes["space"] },
							"assignee",
							{ accountId = M.configs.id }
						)
					)
				end
			elseif k == "summary" then
				table.insert(jobs, M.set_issue_job({ issue_id = attributes["key"], space = attributes["space"] }, k, v))
			end
		end
	end
	return jobs
end

M.update_childs = function(history_issues, buffer_issues, parent_info)
	local jobs = {}
	if transitions[parent_info["parent"]] == nil then
		transitions[parent_info["parent"]] =
			M.get_possibile_transitions({ issue_id = parent_info["parent"], space = parent_info["space"] })
	end

	for _, buffer_issue in ipairs(buffer_issues) do
		if buffer_issue["key"] == "" then
			table.insert(
				jobs,
				M.create_child_job({
					summary = buffer_issue["summary"],
					parent = parent_info["parent"],
					space = parent_info["space"],
				})
			)
		else
			issue = has_key(history_issues, buffer_issue["key"])
			if issue ~= nil then
				if issue["status"] ~= M.icon_to_status(buffer_issue["status"], transitions[parent_info["parent"]]) then
					local target_status = M.icon_to_status(buffer_issue["status"], transitions[parent_info["parent"]])
					table.insert(
						jobs,
						M.transit_issue_job({
							status = target_status,
							key = buffer_issue["key"],
							transition = transitions[parent_info["parent"]][target_status],
							space = parent_info["space"],
						})
					)
				end
				if issue["summary"] ~= buffer_issue["summary"] then
					table.insert(
						jobs,
						M.set_issue_job(
							{ issue_id = buffer_issue["key"], space = parent_info["space"] },
							"summary",
							buffer_issue["summary"]
						)
					)
				end
			end
		end
	end
	return jobs
end

--- Get information for all sections in curenlty opened buffer.
---@param bufnr(number)
---@return table
M.get_sections = function(bufnr)
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
			table.insert(childs, M.fetch_child_info(line))
		end
	end

	return { attributes = attributes, description = sections[2], childs = childs }
end

M.update_all_section = function(bufnr)
	print("Update started")
	if bufnr == nil then
		bufnr = vim.api.nvim_get_current_buf()
	end

	local jobs = {}

	if vim.b[bufnr].is_comment then
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		resp, _ = M.add_comment({
			space = vim.b[bufnr].space,
			issue_id = vim.b[bufnr].key,
			comment = table.concat(lines, "\n"),
		})
		vim.api.nvim_win_close(vim.api.nvim_get_current_win(), true)
		M.reload_issue(vim.b[bufnr].parent_buf)
		return resp
	end

	local sections = M.get_sections(bufnr)

	if sections["attributes"]["key"] == "" and sections["attributes"]["project"] ~= "" then
		M.md_to_task(bufnr)
		return
	end

	local update_attributes_jobs = M.update_attributes(vim.b[bufnr].attributes, sections["attributes"])
	table.append(jobs, update_attributes_jobs)

	local update_description_job = M.set_issue_job(
		{ issue_id = vim.b[bufnr].key, space = vim.b[bufnr].space },
		"description",
		table.concat(sections.description, "\n")
	)
	table.insert(jobs, update_description_job)

	if vim.b[bufnr].key == nil or vim.b[bufnr].subtasks == nil then
		print("Please first reload issue")
		return
	end

	local create_childs_jobs = M.update_childs(
		vim.b[bufnr].subtasks,
		sections["childs"],
		{ parent = vim.b[bufnr].key, space = vim.b[bufnr].space }
	)
	table.append(jobs, create_childs_jobs)

	local open_issue_job = M.get_and_open_issue({ issue_id = vim.b[bufnr].key, space = vim.b[bufnr].space }, bufnr)
	table.insert(jobs, open_issue_job)

	return jobs
end

M.move_issue_to_sprint = function(issue_info, sprint)
	if sprint == "" then
		return
	elseif sprint == "current" then
		sprint = M.configs.sprint_map[vim.split(issue_info["issue_id"], "-")[1]]
	end

	url = "https://" .. issue_info["space"] .. "/rest/agile/1.0/sprint/" .. sprint .. "/issue"

	body = {
		issues = {
			issue_info["issue_id"],
		},
	}
	response, response_code = http_post({ url = url, space = issue_info["space"] }, vim.json.encode(body))

	return response, response_code
end

M.move_issue_to_sprint_job = function(issue_info, sprint)
	if sprint == "" then
		return
	elseif sprint == "current" then
		sprint = M.configs.sprint_map[vim.split(issue_info["issue_id"], "-")[1]]
	end

	body = vim.json.encode({
		issues = {
			issue_info["issue_id"],
		},
	})

	local set_job = curl.post("https://" .. issue_info["space"] .. "/rest/agile/1.0/sprint/" .. sprint .. "/issue", {
		headers = {
			authorization = "Basic " .. mime.b64(
				string.format(
					"%s:%s",
					M.configs.spaces[issue_info["space"]]["email"],
					M.configs.spaces[issue_info["space"]]["token"]
				)
			),
			["Content-Type"] = "application/json",
			["Content-Length"] = body:len(),
		},
		body = body,
		callback = function(out) end,
	})
	return set_job
end

M.create_task = function(info)
	local body = vim.json.encode({
		fields = {
			project = {
				key = info["project"],
			},
			summary = info["summary"],
			issuetype = {
				name = "Task",
			},
			parent = {
				key = info["parent"],
			},
			assignee = {},
			description = info["description"],
		},
	})

	local job_create_task = curl.post("https://" .. info["space"] .. "/rest/api/3/issue/", {
		headers = {
			authorization = "Basic "
				.. mime.b64(string.format("%s:%s", info["space"]["email"], info["space"]["token"])),
			["Content-Type"] = "application/json",
			["Content-Length"] = body:len(),
		},
		body = body,
		callback = function(out) end,
	})

	local response_table = vim.json.decode(response)

	return response_table, response_code
end

--- Create a new issue and open it in a new buffer
---@param bufnr (number) buffer number
M.md_to_task = function(bufnr)
	bufnr = bufnr or 0
	local sections = M.get_sections(bufnr)
	local task_info = sections["attributes"]
	task_info["description"] = M.make_adf(sections["description"])
	task_info["space"] = sections["attributes"]["space"]

	local body = vim.json.encode({
		fields = {
			project = {
				key = task_info["project"],
			},
			summary = task_info["summary"],
			issuetype = {
				name = "Task",
			},
			parent = {
				key = task_info["parent"],
			},
			assignee = {},
			description = task_info["description"],
		},
	})

	local job_create_task = curl.post("https://" .. task_info["space"] .. "/rest/api/3/issue/", {
		headers = {
			authorization = "Basic " .. mime.b64(
				string.format(
					"%s:%s",
					M.configs.spaces[task_info["space"]]["email"],
					M.configs.spaces[task_info["space"]]["token"]
				)
			),
			["Content-Type"] = "application/json",
			["Content-Length"] = body:len(),
		},
		body = body,
		callback = vim.schedule_wrap(function(out)
			local response = vim.json.decode(out.body)

			if response["sprint"] ~= nil then
				M.move_issue_to_sprint_job({ issue_id = response.key, space = task_info["space"] }, task_info["sprint"])
					:start()
			end

			M.open_issue(M.get_issue({ issue_id = response["key"], space = task_info["space"] }))
		end),
	})

	job_create_task:start()
end

M.open_task_template = function(info)
	prefix = info["prefix"] or ""
	project = info["project"] or ""
	parent = info["parent"] or ""
	status = info["status"] or ""
	sprint = info["sprint"] or ""
	space = info["space"] or ""
	priority = info["priority"] or ""

	lines = {
		"<!-- attributes -->",
		"key:",
		"summary:" .. prefix .. "",
		"project:" .. project,
		"parent:" .. parent,
		"status:" .. status,
		"sprint:" .. sprint,
		"space:" .. space,
		"priority:" .. priority,
		"---",
		"<!-- description -->",
		"---",
		"<!-- childs -->",
		"---",
	}
	vim.cmd("enew")
	vim.b.key = "UNDEFINED"
	vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

M.telescope_predefined_templates = function()
	local results = M.configs.templates

	pickers
		.new({}, {
			prompt_title = "Predefined task template",
			results_title = "templates",
			finder = finders.new_table({
				results = results,
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
					print("You picked:", selection.display)
					M.open_task_template(selection.value)
				end)
				return true
			end,
		})
		:find()

	return results
end

M.get_issue_sprint = function(issue)
	for _, field in pairs(issue["fields"]) do
		if type(field) == "table" then
			if #field > 0 and field[1]["boardId"] ~= nil then
				return field[1]["id"]
			end
		end
	end
	return ""
end


M.get_comment = function(issue_info)
	url = "https://"
		.. issue_info["space"]
		.. "/rest/api/2/issue/"
		.. issue_info["issue_id"]
		.. "/comment?expand=renderedBody"
	response, response_code = http_get({ url = url, space = issue_info["space"] })
	local response_table = vim.json.decode(response)
	return response_table["comments"]
end

M.add_comment = function(issue_info)
	url = "https://"
		.. issue_info["space"]
		.. "/rest/api/2/issue/"
		.. issue_info["issue_id"]
		.. "/comment?expand=renderedBody"
	body = {
		body = issue_info["comment"],
	}
	response, response_code = http_post({ url = url, space = issue_info["space"] }, vim.json.encode(body))
	return response, response_code
end

M.setup = function(opts)
	M.opts = setmetatable(opts or {}, { __index = defaults })
	M.initialized = true

	if not Path:new(M.opts.config_path):exists() then
		vim.notify("Jira is not initialized; please check the existance of config file.", 4)
		return
	end
	M.configs = vim.json.decode(vim.fn.readfile(M.opts.config_path))

	if M.configs.spaces == nil then
		vim.notify("Jira space is not defined. set it with token.", 4)
		return
	end

	if not Path:new(M.opts.path_issues):is_dir() then
		Path:new(M.opts.path_issues):mkdir()
	end
end

return M
