local M = {}

local Job = require("plenary.job")
local Path = require("plenary.path")
local curl = require("custom_curl")
local defaults = require("jira.defaults")
local jira = require("jira")
local jui = require("jira.ui")

M.open_issue = function(space, issue_id)
	local issue = nil
	local comments = nil

	job_content = curl.get(string.format("https://%s/rest/api/2/issue/%s?expand=renderedFields", space, issue_id), {
		auth = string.format("%s:%s", jira.configs.spaces[space]["email"], jira.configs.spaces[space]["token"]),
		accept = "application/json",
		callback = vim.schedule_wrap(function(out)
			issue = vim.json.decode(out.body)
		end),
	})

	job_comments = curl.get(string.format("https://%s/rest/api/2/issue/%s/comment", space, issue_id), {
		auth = string.format("%s:%s", jira.configs.spaces[space]["email"], jira.configs.spaces[space]["token"]),
		accept = "application/json",
		callback = vim.schedule_wrap(function(out)
			comments = vim.json.decode(out.body)
			local lines = jui.issue_to_markdown(issue, comments)

			jui.open_float(lines)
			vim.cmd("w! " .. (Path:new(jira.opts.path_issues) / issue.key .. ".md"))

			require("notify")("Issue update done", "info", { { title = "Update done" } })
		end),
	})

	Job.chain(job_content, job_comments)
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










M.test = function()
end

M.test2 = function()
end

	-- jui.open_float(jui.get_issue_template(jira.configs.templates[2]))
--
	-- local tmp1 = jui.read_issue_buf()
	-- M.create_issue("jungyong0615dot.atlassian.net", tmp1.body)
	-- vim.pretty_print(tmp1)
-- M.delete_issue("jungyong0615dot.atlassian.net", 'PRD-41')

return M
