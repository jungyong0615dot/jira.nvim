
	-- M.query_issues(
	-- 	"jungyong0615dot.atlassian.net",
	-- 	'project%20%3D%20Productivity%20AND%20type%20%3D%20Task%20AND%20status%20!%3DClosed%20AND%20status%20%3D%20%22To%20Do%22%20ORDER%20BY%20lastViewed%20DESC'
	-- )
	-- M.update_changed_fields("jungyong0615dot.atlassian.net", "PRD-137")

	-- local issue_id = "PRD-155"
	-- local status = "In Progress"
	--
	-- M.transit_issue("jungyong0615dot.atlassian.net", issue_id, status):start()
  -- 
  -- 
-- jui.open_float(jui.get_issue_template(jira.configs.templates[2]))
--

-- local bufnr = bufnr or 0
-- local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
--  local tmp1 = jui.markdown_to_issue(lines)
-- M.reate_issue("jungyong0615dot.atlassian.net", tmp1.body)
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
 --  local tline = vim.api.nvim_buf_get_lines(0, 0, -1, false)
 --  local cursor = vim.api.nvim_win_get_cursor(0)
 --  local line = tline[cursor[1] - 1]
 --  local issue_id = vim.split(line, "║")[2]
 --  vim.pretty_print(issue_id)
 --   
	-- M.open_issue(vim.b.jira_space, issue_id)

	-- M.open_issue("jungyong0615dot.atlassian.net", "PRD-137")
	-- M.open_issue("jungyong0615dot.atlassian.net", "PRD-137")
	-- M.get_issue_types("jungyong0615dot.atlassian.net", "PRD"):start()
