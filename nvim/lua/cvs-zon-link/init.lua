local M = {}

M.config = {}

local function is_cvs_file(filepath)
    local cvs_dir = vim.fn.fnamemodify(filepath, ":h") .. "/CVS"
    return vim.fn.isdirectory(cvs_dir) ~= 0
end

-- CVS/Root is ":pserver:user@host:/path" (or similar); the cvsweb instance
-- for a given CVS server lives at the same host under the "cvsweb." subdomain.
local function read_cvsweb_base_url(dir)
    local ok, lines = pcall(vim.fn.readfile, dir .. "/CVS/Root")
    if not ok then return nil end
    local host = (lines[1] or ""):match("@([^:]+):")
    if not host then return nil end
    local cvsweb_host = host:gsub("^cvs%.", "cvsweb.")
    return "https://" .. cvsweb_host .. "/cvs"
end

-- CVS/Repository holds the path (relative to the CVS root, e.g. "zon/pkg/...")
-- that this directory's files live under.
local function read_repository(dir)
    local lines = vim.fn.readfile(dir .. "/CVS/Repository")
    return lines[1]
end

-- CVS/Entries holds one line per tracked file: /name/revision/date/options/tag/
-- Reading it avoids a network round-trip to the CVS server for `cvs status`.
local function read_working_revision(dir, fname)
    local ok, lines = pcall(vim.fn.readfile, dir .. "/CVS/Entries")
    if not ok then return nil end
    local pattern = "^/" .. vim.pesc(fname) .. "/([%d%.]+)/"
    for _, line in ipairs(lines) do
        local rev = line:match(pattern)
        if rev then return rev end
    end
    return nil
end

-- Resolve the file + revision CvsZonLink should act on: either the current
-- buffer's own file/working-revision, or, if we're inside a historic
-- revision buffer opened by CvsLog, the file/revision it was fetched from.
local function current_target()
    local source_file = vim.b[0].cvs_log_source_file
    local source_rev   = vim.b[0].cvs_log_source_rev
    if source_file and source_file ~= "" then
        return source_file, source_rev
    end

    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return nil end

    local dir  = vim.fn.fnamemodify(filepath, ":h")
    local fname = vim.fn.fnamemodify(filepath, ":t")
    return filepath, read_working_revision(dir, fname)
end

function M.link()
    local filepath, rev = current_target()
    if not filepath then
        vim.notify("[cvs-zon-link] No file in current buffer", vim.log.levels.WARN)
        return
    end
    if not is_cvs_file(filepath) then
        vim.notify("[cvs-zon-link] Not a CVS-tracked file", vim.log.levels.WARN)
        return
    end
    if not rev then
        vim.notify("[cvs-zon-link] Could not determine CVS revision", vim.log.levels.WARN)
        return
    end

    local dir  = vim.fn.fnamemodify(filepath, ":h")
    local fname = vim.fn.fnamemodify(filepath, ":t")
    local repository = read_repository(dir)
    if not repository then
        vim.notify("[cvs-zon-link] Could not read CVS/Repository", vim.log.levels.WARN)
        return
    end
    local base_url = M.config.base_url or read_cvsweb_base_url(dir)
    if not base_url then
        vim.notify("[cvs-zon-link] Could not read CVS/Root", vim.log.levels.WARN)
        return
    end

    local lineno = vim.api.nvim_win_get_cursor(0)[1]
    local url = string.format("%s/%s/%s?rev=%s#line%d",
        base_url, repository, fname, rev, lineno)

    vim.api.nvim_echo({ { url, "Normal" } }, false, {})
    return url
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    vim.api.nvim_create_user_command("CvsZonLink", M.link, {})
end

return M
