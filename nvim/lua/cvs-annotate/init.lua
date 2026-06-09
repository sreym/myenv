local M = {}

-- Cache: { [filepath] = { data = { [lineno] = entry }, mtime, time } }
local cache = {}
-- Track which files are currently being fetched
local loading = {}
-- Track which buffers have on_lines attached
local attached_bufs = {}

-- Configuration with defaults
M.config = {
    enabled = true,
    format = " %revision | %author | %date", -- format string
    date_format = "%Y-%m-%d",                 -- how to display date
    cache_ttl = 300,                           -- seconds before cache expires
    async = true,                              -- run cvs annotate async
}

local function format_annotation(entry)
    if not entry then return "" end
    local result = M.config.format
    result = result:gsub("%%revision", entry.revision or "?")
    result = result:gsub("%%author",   entry.author   or "?")
    result = result:gsub("%%date",     entry.date     or "?")
    return result
end

local function parse_cvs_annotate(output)
    local lines = {}
    local lineno = 0
    for line in output:gmatch("[^\r\n]+") do
        lineno = lineno + 1
        -- CVS annotate line format:
        -- 1.5          (john     21-Feb-26): actual code here
        local revision, author, date =
            line:match("^%s*([%d%.]+)%s+%(([^%)]+)%s+(%d+%-%a+%-%d+)%)")
        if revision then
            author = author:match("^%s*(.-)%s*$") -- trim whitespace
            lines[lineno] = {
                revision = revision,
                author   = author,
                date     = date,
            }
        end
    end
    return lines
end

-- Called by nvim_buf_attach whenever lines change in the buffer.
-- firstline, lastline, new_lastline are all 0-indexed.
-- Old lines firstline..lastline-1 (0-idx) = firstline+1..lastline (1-idx) are replaced
-- by new_lastline - firstline new lines.
local function on_buf_lines(_, buf, _, firstline, lastline, new_lastline)
    local filepath = vim.api.nvim_buf_get_name(buf)
    if not cache[filepath] then return end

    local data  = cache[filepath].data
    local delta = new_lastline - lastline
    local new_data = {}

    for lineno, entry in pairs(data) do
        if lineno <= firstline then
            -- Before the changed region (1-idx lines 1..firstline): keep as-is
            new_data[lineno] = entry
        elseif lineno > lastline then
            -- After the old region (1-idx lines > lastline): shift by delta
            local shifted = lineno + delta
            if shifted > 0 then
                new_data[shifted] = entry
            end
        end
        -- Lines inside the changed region (1-idx firstline+1..lastline): drop them,
        -- they were modified or deleted so the old annotation no longer applies.
    end

    cache[filepath].data = new_data
end

local function attach_buf(bufnr)
    if attached_bufs[bufnr] then return end
    attached_bufs[bufnr] = true
    vim.api.nvim_buf_attach(bufnr, false, {
        on_lines  = on_buf_lines,
        on_detach = function(_, buf) attached_bufs[buf] = nil end,
    })
end

local function run_cvs_annotate(filepath)
    if loading[filepath] then return end
    loading[filepath] = true

    -- Save mtime to detect file changes
    local mtime = vim.loop.fs_stat(filepath) and
                  vim.loop.fs_stat(filepath).mtime.sec or 0

    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)
    local output = ""

    local handle
    handle = vim.loop.spawn("cvs", {
        args  = { "annotate", vim.fn.fnamemodify(filepath, ":t") },
        stdio = { nil, stdout, stderr },
        cwd   = vim.fn.fnamemodify(filepath, ":h"),
    }, function(code, _signal)
        stdout:close()
        stderr:close()
        handle:close()
        loading[filepath] = nil

        vim.schedule(function()
            if code == 0 then
                cache[filepath] = {
                    data  = parse_cvs_annotate(output),
                    mtime = mtime,
                    time  = os.time(),
                }
                -- Force statusline refresh
                vim.cmd("redrawstatus")
            end
        end)
    end)

    vim.loop.read_start(stdout, function(err, data)
        if not err and data then
            output = output .. data
        end
    end)
    -- Drain stderr silently
    vim.loop.read_start(stderr, function(_, _) end)
end

local function is_cache_valid(filepath)
    if not cache[filepath] then return false end
    -- Expire by TTL
    if (os.time() - cache[filepath].time) > M.config.cache_ttl then
        cache[filepath] = nil
        return false
    end
    -- Expire if file changed on disk (external edit)
    local stat = vim.loop.fs_stat(filepath)
    if stat and stat.mtime.sec ~= cache[filepath].mtime then
        cache[filepath] = nil
        return false
    end
    return true
end

--- Get annotation string for the current cursor line.
--- Returns empty string if not available yet (triggers async fetch).
function M.get_current_line_annotation()
    if not M.config.enabled then return "" end

    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then return "" end

    -- Only work on files tracked by CVS (check for CVS/Entries)
    local cvs_dir = vim.fn.fnamemodify(filepath, ":h") .. "/CVS"
    if vim.fn.isdirectory(cvs_dir) == 0 then return "" end

    -- Attach line-change tracking so the cache stays in sync with edits
    attach_buf(vim.api.nvim_get_current_buf())

    local lineno = vim.api.nvim_win_get_cursor(0)[1]

    if is_cache_valid(filepath) then
        local entry = cache[filepath].data[lineno]
        return format_annotation(entry)
    else
        -- Trigger async fetch (non-blocking)
        if not loading[filepath] then
            run_cvs_annotate(filepath)
        end
        return " ⟳ loading…"
    end
end

--- Manually clear cache for the current buffer
function M.clear_cache()
    local filepath = vim.api.nvim_buf_get_name(0)
    cache[filepath] = nil
    loading[filepath] = nil
    vim.notify("[cvs-annotate] Cache cleared for " .. filepath, vim.log.levels.INFO)
end

--- Refresh annotation for the current buffer
function M.refresh()
    local filepath = vim.api.nvim_buf_get_name(0)
    cache[filepath] = nil
    loading[filepath] = nil
    run_cvs_annotate(filepath)
    vim.notify("[cvs-annotate] Refreshing CVS annotation…", vim.log.levels.INFO)
end

--- Setup the plugin
function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    -- Auto-refresh cache when a buffer is saved
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = vim.api.nvim_create_augroup("CvsAnnotate", { clear = true }),
        callback = function()
            local fp = vim.api.nvim_buf_get_name(0)
            cache[fp] = nil
            loading[fp] = nil
            run_cvs_annotate(fp)
        end,
    })

    -- User commands
    vim.api.nvim_create_user_command("CvsAnnotateRefresh", M.refresh, {})
    vim.api.nvim_create_user_command("CvsAnnotateClear",   M.clear_cache, {})
    vim.api.nvim_create_user_command("CvsAnnotateToggle", function()
        M.config.enabled = not M.config.enabled
        vim.notify("[cvs-annotate] " ..
            (M.config.enabled and "Enabled" or "Disabled"),
            vim.log.levels.INFO)
        vim.cmd("redrawstatus")
    end, {})
end

return M
