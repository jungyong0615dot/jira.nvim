local M = {}

local curl = require("custom_curl")
local defaults = require("jira.defaults")
local jira = require("jira")

local function get_auth(space, type)
	if type == "get" then
		return string.format("%s:%s", jira.configs.spaces[space]["email"], jira.configs.spaces[space]["token"])
	else
		return { [jira.configs.spaces[space]["email"]] = jira.configs.spaces[space]["token"] }
	end
end

M.encodeURI = function (str)

  if (str) then
    str = string.gsub (str, "\n", "\r\n")
    str = string.gsub (str, "([^%w ])",
        function (c) return string.format ("%%%02X", string.byte(c)) end)
    str = string.gsub (str, " ", "+")
  end
  return str	
end


M.get = function(space, url, callback)
	return curl.get(string.format("https://%s/rest/api/2/%s", space, url), {
		auth = get_auth(space, "get"),
		accept = "application/json",
		callback = vim.schedule_wrap(callback),
	})
end

M.put = function(space, url, body, callback)
	return curl.put(string.format("https://%s/rest/api/2/%s", space, url), {
		auth = get_auth(space, "put"),
		headers = {
			content_type = "application/json",
		},
		body = body,
		callback = vim.schedule_wrap(callback),
	})
end

M.post = function(space, url, body, callback)
	return curl.post(string.format("https://%s/rest/api/2/%s", space, url), {
		auth = get_auth(space, "post"),
		headers = {
			content_type = "application/json",
		},
		body = body,
		callback = vim.schedule_wrap(callback),
	})
end

M.delete = function(space, url, callback)
	return curl.delete(string.format("https://%s/rest/api/2/%s", space, url), {
		auth = get_auth(space, "delete"),
		callback = vim.schedule_wrap(callback),
	})
end

return M
