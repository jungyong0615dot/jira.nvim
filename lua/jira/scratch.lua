local M = {}

local Job = require("plenary.job")
local Path = require("plenary.path")
local curl = require("custom_curl")
local defaults = require("jira.defaults")
local jira = require("jira")
local jui = require("jira.ui")

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

	job_content = curl.get(string.format("https://%s/rest/api/2/issue/%s?expand=renderedFields", space, issue_id), {
		auth = string.format("%s:%s", jira.configs.spaces[space]["email"], jira.configs.spaces[space]["token"]),
		accept = "application/json",
		callback = vim.schedule_wrap(function(out)
			issue = vim.json.decode(out.body)
			comments = issue.fields.comment.comments
			local lines = jui.issue_to_markdown(issue, comments)

			jui.open_float(lines)
			vim.cmd("w! " .. (Path:new(jira.opts.path_issues) / issue.key .. ".md"))

			vim.notify("Issue " .. issue.key .. " opened")
		end),
	}):start()
end

M.query_issues = function(space, query)
	local issues = nil
	local job = curl.get(string.format("https://%s/rest/api/2/search?jql=%s", space, query), {
		auth = string.format("%s:%s", jira.configs.spaces[space]["email"], jira.configs.spaces[space]["token"]),
		accept = "application/json",
		callback = vim.schedule_wrap(function(out)
			issues = vim.json.decode(out.body)
			jui.issues_picker(issues)
		end),
	}):start()
end

M.create_issue = function(space, body)
	local job = curl.post(string.format("https://%s/rest/api/2/issue/", space), {

		auth = { [jira.configs.spaces[space]["email"]] = jira.configs.spaces[space]["token"] },
		headers = {
			content_type = "application/json",
		},
		body = body,
		callback = vim.schedule_wrap(function(out)
			local issue = vim.json.decode(out.body)
		end),
	}):start()
end

M.delete_issue = function(space, issue_id)
	local job = curl.delete(string.format("https://%s/rest/api/2/issue/%s", space, issue_id), {
		auth = { [jira.configs.spaces[space]["email"]] = jira.configs.spaces[space]["token"] },
		accept = "application/json",
		callback = vim.schedule_wrap(function(out)
			if out.status == 204 then
				vim.notify("Issue deleted", "info", { title = "Delete done" })
			else
				vim.notify("Error deleting issue", "error", { title = "Delete error" })
			end
		end),
	}):start()
end

--- Update issue with given body
---@param space
---@param issue_id
---@param body
---@param out
M.update_issue = function(space, issue_id, body)
	local job_write = curl.put(string.format("https://%s/rest/api/2/issue/%s", space, issue_id), {
		auth = { [jira.configs.spaces[space]["email"]] = jira.configs.spaces[space]["token"] },
		headers = {
			content_type = "application/json",
		},
		body = body,
		callback = vim.schedule_wrap(function(out)
			if out.status == 204 then
				vim.notify("Issue updated", "info", { title = "Update done" })
			else
				vim.notify("Error updating issue", "error", { title = "Update error" })
			end
		end),
	}):start()
end

--- Update issue with given issue_id. read content from current buffer
---@param space
---@param issue_id
---@param out
M.update_changed_fields = function(space, issue_id)
	local fields_to_update = { "summary" }

	local remote_issue = nil
	local local_issue = nil
	local remote_comments = nil
	local local_comments = nil
	local is_changed = false
	local body = { fields = {} }

	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local_issue = jui.markdown_to_issue(lines)

	local job_read = curl.get(string.format("https://%s/rest/api/2/issue/%s?expand=renderedFields", space, issue_id), {
		auth = string.format("%s:%s", jira.configs.spaces[space]["email"], jira.configs.spaces[space]["token"]),
		accept = "application/json",
		callback = vim.schedule_wrap(function(out)
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
			-- update description
			if local_issue.description ~= remote_issue.fields.description then
				body.fields["description"] = local_issue.description
			end

			local job_update = curl.put(string.format("https://%s/rest/api/2/issue/%s", space, issue_id), {
				auth = { [jira.configs.spaces[space]["email"]] = jira.configs.spaces[space]["token"] },
				headers = {
					content_type = "application/json",
				},
				body = vim.json.encode(body),
				callback = vim.schedule_wrap(function(out)
					if out.status == 204 then
						vim.notify("Issue updated", "info", { title = "Update done" })
					else
						vim.notify("Error updating issue", "error", { title = "Update error" })
					end
				end),
			})

			-- updae status
      local job_transit = nil
			if local_issue.attributes["status"] ~= jui.status_to_icon(remote_issue.fields.status.name) then
				job_transit = M.transit_issue(space, issue_id, local_issue.attributes["status"])
			end
      

  local job_redraw = curl.get(string.format("https://%s/rest/api/2/issue/%s?expand=renderedFields", space, issue_id), {
    auth = string.format("%s:%s", jira.configs.spaces[space]["email"], jira.configs.spaces[space]["token"]),
    accept = "application/json",
    callback = vim.schedule_wrap(function(out)
      issue = vim.json.decode(out.body)
      comments = issue.fields.comment.comments
      local newlines = jui.issue_to_markdown(issue, comments)

      vim.notify("Issue " .. issue.key .. " redrawn")
      vim.api.nvim_buf_set_lines(0, 0, -1, false, newlines)
      
      
    end),
  })
  
    Job.chain(job_update, job_transit, job_redraw)
      
		end),
	}):start()
  
  
end


--- Transit issue with given issue_id to given status
---@param space 
---@param issue_id 
---@param target_status: str. Name like "To Do" or icon like "-" defined in ui.status_map
M.transit_issue = function(space, issue_id, target_status)
  
	local prj = string.match(issue_id, "[^-]+")
	local map_by_prj =
		vim.json.decode(table.concat(vim.fn.readfile(jira.opts.transits_path), ""))

	local target_icon = nil
	if target_status:len() < 2 then
		target_icon = target_status
	else
		target_icon = jui.status_to_icon(target_status)
	end

	if map_by_prj[prj] ~= nil then
    -- TODO: make it as an function
		local prj_status = jui.icon_to_status(target_icon, map_by_prj[prj])
		local transition_id = map_by_prj[prj][prj_status]

		return curl.post(string.format("https://%s/rest/api/2/issue/%s/transitions", space, issue_id), {
			auth = { [jira.configs.spaces[space]["email"]] = jira.configs.spaces[space]["token"] },
			headers = {
				content_type = "application/json",
			},
			body = vim.json.encode({
				transition = {
					id = transition_id,
				},
			}),
			callback = vim.schedule_wrap(function(out)
				if out.status == 204 then
					vim.notify("issue transition success", "info", { title = "Update done" })
				else
          vim.pretty_print(out)
					vim.notify("Error in issue transition", "error", { title = "Update error" })
				end
			end),
		})
    
	else
		return curl.get(string.format("https://%s/rest/api/3/issue/%s/transitions", space, issue_id), {
			auth = string.format("%s:%s", jira.configs.spaces[space]["email"], jira.configs.spaces[space]["token"]),
			accept = "application/json",
			callback = vim.schedule_wrap(function(out)
				local response_table = vim.json.decode(out.body)
        local transitions = {}
        vim.pretty_print(response_table)
				for _, v in ipairs(response_table.transitions) do
					transitions[v.name] = v.id
				end
				map_by_prj[prj] = transitions

				vim.fn.writefile(
					vim.split(vim.json.encode(map_by_prj), "\n"),
					jira.opts.transits_path
				)
        local prj_status = jui.icon_to_status(target_icon, map_by_prj[prj])
        local transition_id = map_by_prj[prj][prj_status]

        local _ = curl.post(string.format("https://%s/rest/api/2/issue/%s/transitions", space, issue_id), {
          auth = { [jira.configs.spaces[space]["email"]] = jira.configs.spaces[space]["token"] },
          headers = {
            content_type = "application/json",
          },
          body = vim.json.encode({
            transition = {
              id = transition_id,
            },
          }),
          callback = vim.schedule_wrap(function(out)
            if out.status == 204 then
              vim.notify("issue transition success", "info", { title = "Update done" })
            else
              vim.pretty_print(out)
              vim.notify("Error in issue transition 2", "error", { title = "Update error" })
              vim.pretty_print(out)
            end
          end),
        }):start()
			end),
		})

	end
end

M.test = function()
  M.open_issue("jungyong0615dot.atlassian.net", "PRD-155")
end

M.test2 = function()
	M.update_changed_fields("jungyong0615dot.atlassian.net", "PRD-155")
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
