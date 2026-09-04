local M = {}

-- Per-tab state, keyed by tabpage handle, so CvsLog can be open independently
-- in different tabs.
local states = {}

local function get_state(tabid)
    tabid = tabid or vim.api.nvim_get_current_tabpage()
    local s = states[tabid]
    if not s then
        s = {
            buf      = nil,
            win      = nil,
            loading  = {},
            filepath = nil,
            -- line (1-idx) -> index into `revisions`, for every line belonging to that revision's block
            line_map  = {},
            revisions = {},
            -- currently open historic-revision buffer (opened via <CR>), if any
            open_revision = nil,
        }
        states[tabid] = s
    end
    return s
end

-- Prune state for tabs that no longer have a live panel window, whenever any
-- tab closes (handles are never reused, so this keeps the table bounded).
vim.api.nvim_create_autocmd("TabClosed", {
    callback = function()
        for tabid, s in pairs(states) do
            if not (s.win and vim.api.nvim_win_is_valid(s.win)) then
                states[tabid] = nil
            end
        end
    end,
})

M.config = {
    width = 60,
}

local SEP = string.rep("-", 60)
local highlight_ns = vim.api.nvim_create_namespace("cvs_log_highlight")

local function is_cvs_file(filepath)
    local cvs_dir = vim.fn.fnamemodify(filepath, ":h") .. "/CVS"
    return vim.fn.isdirectory(cvs_dir) ~= 0
end

local function set_buf_lines(buf, lines)
    vim.api.nvim_set_option_value("modifiable", true,  { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

-- Parse the output of `cvs log` into a list of
-- { revision, date, author, comment = { line1, line2, ... } }
local function parse_cvs_log(output)
    local lines = vim.split(output, "\n", { plain = true })
    local revisions = {}
    local i = 1
    while i <= #lines do
        local rev = lines[i]:match("^revision%s+(%S+)")
        if rev then
            local meta = lines[i + 1] or ""
            local date, time, author =
                meta:match("date:%s*(%S+)%s+(%S+)[^;]*;%s*author:%s*([^;]+);")
            author = author and author:match("^%s*(.-)%s*$") or "?"

            local comment = {}
            local j = i + 2
            while j <= #lines
                and not lines[j]:match("^%-%-%-%-+$")
                and not lines[j]:match("^=%=%=%=+$")
            do
                table.insert(comment, lines[j])
                j = j + 1
            end
            while #comment > 0 and comment[#comment] == "" do
                table.remove(comment)
            end

            table.insert(revisions, {
                revision = rev,
                date     = (date and time) and (date .. " " .. time) or "?",
                author   = author,
                comment  = comment,
            })
            i = j
        else
            i = i + 1
        end
    end
    return revisions
end

-- Build the compact display lines, a line -> revision-index map, and
-- per-revision { start, finish } line ranges (1-idx, inclusive).
local function render_revisions(revisions)
    local lines = {}
    local map = {}
    local blocks = {}

    for idx, r in ipairs(revisions) do
        local block_start = #lines + 1
        table.insert(lines, SEP)
        table.insert(lines, string.format("%s - %s - %s", r.revision, r.date, r.author))
        for _, c in ipairs(r.comment) do
            table.insert(lines, c)
        end
        for ln = block_start, #lines do
            map[ln] = idx
        end
        blocks[idx] = { start = block_start, finish = #lines }
    end
    table.insert(lines, SEP)

    if #revisions == 0 then
        lines = { "No revisions found" }
    end

    return lines, map, blocks
end

local function get_revision_under_cursor(st)
    if not (st.win and vim.api.nvim_win_is_valid(st.win)) then return nil end
    local lnum = vim.api.nvim_win_get_cursor(st.win)[1]
    local idx = st.line_map[lnum]
    if not idx then return nil end
    return st.revisions[idx]
end

-- Close the currently open historic-revision buffer (if any) and restore
-- its window to the live buffer. Safe to call when nothing is open.
local function close_open_revision(st)
    local o = st.open_revision
    if not o then return end
    st.open_revision = nil
    if vim.api.nvim_win_is_valid(o.win) then
        vim.api.nvim_win_set_buf(o.win, o.live_buf)
    end
    if vim.api.nvim_buf_is_valid(o.buf) then
        vim.api.nvim_buf_delete(o.buf, { force = true })
    end
    if st.win and vim.api.nvim_win_is_valid(st.win) then
        vim.api.nvim_set_current_win(st.win)
    end
end

-- Fetch `cvs update -p -r <rev>` output for the given revision and invoke
-- on_success(output) once it's ready (scheduled on the main loop).
local function fetch_revision_content(filepath, rev, on_success)
    local dir   = vim.fn.fnamemodify(filepath, ":h")
    local fname = vim.fn.fnamemodify(filepath, ":t")

    local stdout, stderr = vim.loop.new_pipe(false), vim.loop.new_pipe(false)
    local output, err_out = "", ""

    local handle
    handle = vim.loop.spawn("cvs", {
        args  = { "update", "-p", "-r", rev.revision, fname },
        stdio = { nil, stdout, stderr },
        cwd   = dir,
    }, function(code, _signal)
        stdout:close()
        stderr:close()
        handle:close()

        vim.schedule(function()
            if code ~= 0 then
                vim.notify("[cvs-log] Failed to fetch revision " .. rev.revision .. ":\n" .. err_out,
                    vim.log.levels.ERROR)
                return
            end
            on_success(output)
        end)
    end)

    vim.loop.read_start(stdout, function(err, data) if not err and data then output  = output  .. data end end)
    vim.loop.read_start(stderr, function(err, data) if not err and data then err_out = err_out .. data end end)

    vim.notify("[cvs-log] Fetching revision " .. rev.revision .. "…", vim.log.levels.INFO)
end

-- Fill a scratch buffer with revision content and mark it read-only.
local function fill_readonly_revision_buf(buf, filepath, rev, output)
    local fname = vim.fn.fnamemodify(filepath, ":t")
    vim.api.nvim_buf_set_name(buf, fname .. "@" .. rev.revision)
    vim.api.nvim_set_option_value("buftype",   "nofile", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(output, "\n", { plain = true }))

    local ft = vim.filetype.match({ filename = filepath })
    if ft then
        vim.api.nvim_set_option_value("filetype", ft, { buf = buf })
    end

    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("readonly",   true,  { buf = buf })

    -- Remember the real, on-disk file this revision came from (and which
    -- revision it is) so CvsLog can still find the CVS-tracked file and
    -- highlight the matching entry when opened from here.
    vim.b[buf].cvs_log_source_file = filepath
    vim.b[buf].cvs_log_source_rev  = rev.revision
end

local function open_revision_readonly()
    local tabid = vim.api.nvim_get_current_tabpage()
    local st    = get_state(tabid)
    local rev   = get_revision_under_cursor(st)
    if not rev or not st.filepath then return end
    local filepath = st.filepath

    fetch_revision_content(filepath, rev, function(output)
        st = get_state(tabid)
        close_open_revision(st)

        vim.cmd("wincmd p")
        local target_win = vim.api.nvim_get_current_win()
        local live_buf   = vim.api.nvim_get_current_buf()

        vim.cmd("enew")
        local buf = vim.api.nvim_get_current_buf()
        fill_readonly_revision_buf(buf, filepath, rev, output)

        st.open_revision = { win = target_win, buf = buf, live_buf = live_buf }

        -- 'q' returns to the live buffer (also works from the log panel)
        vim.keymap.set("n", "q", function() close_open_revision(get_state(tabid)) end,
            { buffer = buf, silent = true })

        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer   = buf,
            once     = true,
            callback = function()
                local s = get_state(tabid)
                if s.open_revision and s.open_revision.buf == buf then
                    s.open_revision = nil
                end
            end,
        })
    end)
end

-- Open the revision in a brand-new tab, independent of the 'q'/open_revision
-- tracking used for the in-place read-only view.
local function open_revision_in_tab()
    local st  = get_state()
    local rev = get_revision_under_cursor(st)
    if not rev or not st.filepath then return end
    local filepath = st.filepath

    fetch_revision_content(filepath, rev, function(output)
        vim.cmd("tabnew")
        local buf = vim.api.nvim_get_current_buf()
        fill_readonly_revision_buf(buf, filepath, rev, output)
    end)
end

local function show_diff_with_current()
    local tabid = vim.api.nvim_get_current_tabpage()
    local st    = get_state(tabid)
    local rev   = get_revision_under_cursor(st)
    if not rev or not st.filepath then return end

    local filepath = st.filepath
    local dir      = vim.fn.fnamemodify(filepath, ":h")
    local fname    = vim.fn.fnamemodify(filepath, ":t")

    local stdout, stderr = vim.loop.new_pipe(false), vim.loop.new_pipe(false)
    local output, err_out = "", ""

    local handle
    handle = vim.loop.spawn("cvs", {
        args  = { "update", "-p", "-r", rev.revision, fname },
        stdio = { nil, stdout, stderr },
        cwd   = dir,
    }, function(code, _signal)
        stdout:close()
        stderr:close()
        handle:close()

        vim.schedule(function()
            if code ~= 0 then
                vim.notify("[cvs-log] Failed to fetch revision " .. rev.revision .. ":\n" .. err_out,
                    vim.log.levels.ERROR)
                return
            end

            -- Close the log panel and do the comparison in the current tab:
            -- the live file keeps its own buffer/window (untouched, only
            -- entering diff mode); the historic revision gets a brand-new
            -- read-only buffer in a new split.
            M.close()
            local live_win = vim.api.nvim_get_current_win()

            vim.cmd("vsplit")
            local old_win = vim.api.nvim_get_current_win()
            local old_buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_name(old_buf, fname .. "@" .. rev.revision)
            vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, vim.split(output, "\n", { plain = true }))

            local ft = vim.filetype.match({ filename = filepath })
            if ft then
                vim.api.nvim_set_option_value("filetype", ft, { buf = old_buf })
            end
            vim.api.nvim_set_option_value("buftype",   "nofile", { buf = old_buf })
            vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = old_buf })

            vim.api.nvim_win_set_buf(old_win, old_buf)

            vim.api.nvim_set_option_value("modifiable", false, { buf = old_buf })
            vim.api.nvim_set_option_value("readonly",   true,  { buf = old_buf })

            vim.api.nvim_win_call(old_win,  function() vim.cmd("diffthis") end)
            vim.api.nvim_win_call(live_win, function() vim.cmd("diffthis") end)

            -- Restore the live window's normal state once the historic side closes
            vim.api.nvim_create_autocmd("WinClosed", {
                pattern  = tostring(old_win),
                once     = true,
                callback = function()
                    if vim.api.nvim_win_is_valid(live_win) then
                        vim.api.nvim_win_call(live_win, function() vim.cmd("diffoff") end)
                    end
                end,
            })
        end)
    end)

    vim.loop.read_start(stdout, function(err, data) if not err and data then output  = output  .. data end end)
    vim.loop.read_start(stderr, function(err, data) if not err and data then err_out = err_out .. data end end)

    vim.notify("[cvs-log] Diffing against revision " .. rev.revision .. "…", vim.log.levels.INFO)
end

local HELP_LINES = {
    " CVS Log — keys ",
    "",
    " <CR>  open revision read-only here",
    " t     open revision read-only in a new tab",
    " d     close log, vimdiff revision vs current file",
    " q     close open revision, or close the log panel",
    " ?     toggle this help",
}

local help_state = { buf = nil, win = nil }

local function close_help()
    if help_state.win and vim.api.nvim_win_is_valid(help_state.win) then
        vim.api.nvim_win_close(help_state.win, true)
    end
    help_state.win = nil
end

local function show_help()
    if help_state.win and vim.api.nvim_win_is_valid(help_state.win) then
        close_help()
        return
    end

    local width = 0
    for _, l in ipairs(HELP_LINES) do width = math.max(width, #l) end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, HELP_LINES)
    vim.api.nvim_set_option_value("bufhidden",  "wipe", { buf = buf })
    vim.api.nvim_set_option_value("modifiable", false,  { buf = buf })

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width    = width,
        height   = #HELP_LINES,
        row      = math.floor((vim.o.lines   - #HELP_LINES) / 2),
        col      = math.floor((vim.o.columns - width) / 2),
        style    = "minimal",
        border   = "rounded",
    })

    help_state.buf = buf
    help_state.win = win

    for _, key in ipairs({ "q", "?", "<Esc>" }) do
        vim.keymap.set("n", key, close_help, { buffer = buf, silent = true })
    end
end

local function create_buf(tabid)
    local buf = vim.api.nvim_create_buf(false, true)
    -- Buffer names must be unique; disambiguate per tab.
    vim.api.nvim_buf_set_name(buf, string.format("[CVS Log %d]", tabid))
    vim.api.nvim_set_option_value("buftype",   "nofile", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = buf })
    vim.api.nvim_set_option_value("filetype",  "cvs-log",{ buf = buf })
    vim.api.nvim_set_option_value("modifiable", false,   { buf = buf })

    vim.keymap.set("n", "<CR>", open_revision_readonly, { buffer = buf, silent = true })
    vim.keymap.set("n", "d",    show_diff_with_current,  { buffer = buf, silent = true })
    vim.keymap.set("n", "t",    open_revision_in_tab,    { buffer = buf, silent = true })
    vim.keymap.set("n", "?",    show_help,               { buffer = buf, silent = true })
    vim.keymap.set("n", "q", function()
        local st = get_state()
        if st.open_revision then
            close_open_revision(st)
        else
            M.close()
        end
    end, { buffer = buf, silent = true })

    return buf
end

local function open_panel()
    local tabid = vim.api.nvim_get_current_tabpage()
    local st    = get_state(tabid)
    if st.win and vim.api.nvim_win_is_valid(st.win) then return end

    st.buf = create_buf(tabid)

    vim.cmd("topleft vsplit")
    st.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(st.win, st.buf)
    vim.api.nvim_win_set_width(st.win, M.config.width)

    vim.api.nvim_set_option_value("winfixwidth",     true, { win = st.win })
    vim.api.nvim_set_option_value("number",         false, { win = st.win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = st.win })
    vim.api.nvim_set_option_value("wrap",            true, { win = st.win })
    vim.api.nvim_set_option_value("signcolumn",      "no", { win = st.win })
end

-- Move the cursor to and highlight the block for `revision`, if present.
local function select_revision(st, revision, blocks)
    if not revision then return end
    vim.api.nvim_buf_clear_namespace(st.buf, highlight_ns, 0, -1)

    for idx, r in ipairs(st.revisions) do
        if r.revision == revision then
            local block = blocks[idx]
            for ln = block.start, block.finish do
                vim.api.nvim_buf_add_highlight(st.buf, highlight_ns, "Visual", ln - 1, 0, -1)
            end
            if st.win and vim.api.nvim_win_is_valid(st.win) then
                vim.api.nvim_win_set_cursor(st.win, { block.start, 0 })
            end
            return
        end
    end
end

local function run_cvs_log(filepath, select_rev)
    local tabid = vim.api.nvim_get_current_tabpage()
    local st    = get_state(tabid)
    if st.loading[filepath] then return end
    st.loading[filepath] = true

    set_buf_lines(st.buf, { "Loading CVS log…" })

    local stdout    = vim.loop.new_pipe(false)
    local stderr    = vim.loop.new_pipe(false)
    local output    = ""
    local err_out   = ""

    local handle
    handle = vim.loop.spawn("cvs", {
        args  = { "log", vim.fn.fnamemodify(filepath, ":t") },
        stdio = { nil, stdout, stderr },
        cwd   = vim.fn.fnamemodify(filepath, ":h"),
    }, function(code, _signal)
        stdout:close()
        stderr:close()
        handle:close()
        st.loading[filepath] = nil

        vim.schedule(function()
            if not (st.buf and vim.api.nvim_buf_is_valid(st.buf)) then return end
            if code == 0 then
                st.filepath  = filepath
                st.revisions = parse_cvs_log(output)
                local lines, map, blocks = render_revisions(st.revisions)
                st.line_map = map
                set_buf_lines(st.buf, lines)
                select_revision(st, select_rev, blocks)
            else
                st.revisions = {}
                st.line_map  = {}
                set_buf_lines(st.buf, vim.list_extend({ "CVS log failed:" }, vim.split(err_out, "\n", { plain = true })))
            end
        end)
    end)

    vim.loop.read_start(stdout, function(err, data)
        if not err and data then output  = output  .. data end
    end)
    vim.loop.read_start(stderr, function(err, data)
        if not err and data then err_out = err_out .. data end
    end)
end

-- Resolve the file CvsLog should act on for the current buffer: either the
-- buffer's own name, or, if we're inside a historic-revision scratch buffer,
-- the real on-disk file it was fetched from.
local function current_target_file()
    local source = vim.b[0].cvs_log_source_file
    if source and source ~= "" then return source end
    return vim.api.nvim_buf_get_name(0)
end

function M.open()
    local filepath = current_target_file()
    local rev      = vim.b[0].cvs_log_source_rev
    if filepath == "" then
        vim.notify("[cvs-log] No file in current buffer", vim.log.levels.WARN)
        return
    end
    if not is_cvs_file(filepath) then
        vim.notify("[cvs-log] Not a CVS-tracked file", vim.log.levels.WARN)
        return
    end
    open_panel()
    run_cvs_log(filepath, rev)
end

function M.close()
    local st = get_state()
    if st.win and vim.api.nvim_win_is_valid(st.win) then
        vim.api.nvim_win_close(st.win, true)
        st.win = nil
    end
end

function M.toggle()
    local st = get_state()
    if st.win and vim.api.nvim_win_is_valid(st.win) then
        M.close()
    else
        M.open()
    end
end

function M.refresh()
    local filepath = current_target_file()
    local rev      = vim.b[0].cvs_log_source_rev
    if filepath == "" or not is_cvs_file(filepath) then return end
    local st = get_state()
    if not (st.win and vim.api.nvim_win_is_valid(st.win)) then
        M.open()
        return
    end
    st.loading[filepath] = nil
    run_cvs_log(filepath, rev)
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    vim.api.nvim_create_user_command("CvsLog",        M.toggle,  {})
    vim.api.nvim_create_user_command("CvsLogOpen",    M.open,    {})
    vim.api.nvim_create_user_command("CvsLogClose",   M.close,   {})
    vim.api.nvim_create_user_command("CvsLogRefresh", M.refresh, {})
end

return M
