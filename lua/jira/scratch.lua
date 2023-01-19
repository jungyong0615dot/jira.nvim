local M = {}

local Job = require("plenary.job")
local Path = require("plenary.path")
local curl = require("custom_curl")
local defaults = require'jira.defaults'

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
      vim.pretty_print(comments)
    end),
  })

  Job.chain(job_content, job_comments)
end


return M
