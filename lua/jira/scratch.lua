local M = {}

local Job = require("plenary.job")
local Path = require("plenary.path")
local curl = require("custom_curl")
local defaults = require'jira.defaults'
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
      vim.cmd("w " .. (Path:new(jira.opts.path_issues) / issue.key .. ".md!"))

			require("notify")("Issue update done", "info", { { title = "Update done" } })

    end),
  })

  Job.chain(job_content, job_comments)
end


return M
