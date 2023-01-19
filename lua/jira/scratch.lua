local M = {}

local Job = require("plenary.job")
local Path = require("plenary.path")
local curl = require("custom_curl")

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
end

M.setup = function(opts)
	M.opts = setmetatable(opts or {}, { __index = defaults })
	M.initialized = true

	if not Path:new(M.opts.config_path):exists() then
		vim.notify("Jira is not initialized; please check the existance of config file.", 4)
		return
	end
	M.configs = vim.json.decode(vim.fn.readfile(M.opts.config_path))
  vim.notify("loaded config.")

	if M.configs.spaces == nil then
		vim.notify("Jira space is not defined. set it with token.", 4)
		return
	end

	if not Path:new(M.opts.path_issues):is_dir() then
		Path:new(M.opts.path_issues):mkdir()
	end
end

return M
