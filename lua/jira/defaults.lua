local M = {}

M.config_path = os.getenv("HOME") .. "/.nvim/jira.json"
M.transits_path = os.getenv("HOME") .. "/.nvim/jira_map.json"
M.issuetypes_path = os.getenv("HOME") .. "/.nvim/jira_issue_types.json"
M.path_issues = os.getenv("HOME") .. "/.nvim/jira"

return M
