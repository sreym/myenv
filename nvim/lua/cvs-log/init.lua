local M = {}

local state = {
    buf     = nil,
    win     = nil,
    loading = {},
}

M.config = {
    width = 60,
}

local function is_cvs_file(filepath)
    local cvs_dir = vim.fn.fnamemodify(filepath, ":h") .. "/CVS"
    return vim.fn.isdirectory(cvs_dir) ~= 0
end

local function set_buf_lines(lines)
    vim.api.nvim_set_option_value("modifiable", true,  { buf = state.buf })
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
end

local function create_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "[CVS Log]")
    vim.api.nvim_set_option_value("buftype",   "nofile", { buf = buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe",   { buf = buf })
    vim.api.nvim_set_option_value("filetype",  "cvs-log",{ buf = buf })
    vim.api.nvim_set_option_value("modifiable", false,   { buf = buf })
    return buf
end

local function open_panel()
    if state.win and vim.api.nvim_win_is_valid(state.win) then return end

    state.buf = create_buf()

    vim.cmd("topleft vsplit")
    state.win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(state.win, state.buf)
    vim.api.nvim_win_set_width(state.win, M.config.width)

    vim.api.nvim_set_option_value("winfixwidth",     true, { win = state.win })
    vim.api.nvim_set_option_value("number",         false, { win = state.win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = state.win })
    vim.api.nvim_set_option_value("wrap",            true, { win = state.win })
    vim.api.nvim_set_option_value("signcolumn",      "no", { win = state.win })

    vim.cmd("wincmd p")
end

local function run_cvs_log(filepath)
    if state.loading[filepath] then return end
    state.loading[filepath] = true

    set_buf_lines({ "Loading CVS log…" })

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
        state.loading[filepath] = nil

        vim.schedule(function()
            if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then return end
            if code == 0 then
                set_buf_lines(vim.split(output, "\n", { plain = true }))
            else
                set_buf_lines(vim.list_extend({ "CVS log failed:" }, vim.split(err_out, "\n", { plain = true })))
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

function M.open()
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" then
        vim.notify("[cvs-log] No file in current buffer", vim.log.levels.WARN)
        return
    end
    if not is_cvs_file(filepath) then
        vim.notify("[cvs-log] Not a CVS-tracked file", vim.log.levels.WARN)
        return
    end
    open_panel()
    run_cvs_log(filepath)
end

function M.close()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        vim.api.nvim_win_close(state.win, true)
        state.win = nil
    end
end

function M.toggle()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
        M.close()
    else
        M.open()
    end
end

function M.refresh()
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath == "" or not is_cvs_file(filepath) then return end
    if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
        M.open()
        return
    end
    state.loading[filepath] = nil
    run_cvs_log(filepath)
end

function M.setup(opts)
    M.config = vim.tbl_deep_extend("force", M.config, opts or {})

    vim.api.nvim_create_user_command("CvsLog",        M.toggle,  {})
    vim.api.nvim_create_user_command("CvsLogOpen",    M.open,    {})
    vim.api.nvim_create_user_command("CvsLogClose",   M.close,   {})
    vim.api.nvim_create_user_command("CvsLogRefresh", M.refresh, {})
end

return M
