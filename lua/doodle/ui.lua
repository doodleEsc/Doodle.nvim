-- lua/doodle/ui.lua
local utils = require("doodle.utils")
local agent = require("doodle.agent")
local M = {}

-- UI状态
M.UI_STATUS = {
    CLOSED = "closed",
    OPEN = "open",
    MINIMIZED = "minimized"
}

-- 生成状态
M.GENERATE_STATUS = {
    IDLE = "idle",
    GENERATING = "generating",
    TOOL_CALLING = "tool_calling",
    SUCCEEDED = "succeeded",
    FAILED = "failed"
}

-- UI组件
M.ui = {
    status = M.UI_STATUS.CLOSED,
    output_split = nil,     -- 输出组件（主要区域）
    input_split = nil,      -- 输入组件
    status_split = nil,     -- 状态指示器
    output_buffer = nil,
    input_buffer = nil,
    status_buffer = nil,
    current_state = M.GENERATE_STATUS.IDLE,
    augroup = nil,
    winids = {},
    scroll_enabled = true,
}

-- Helper to temporarily make a buffer writable
function M.with_writable_buffer(bufnr, callback)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local original_modifiable = vim.api.nvim_buf_get_option(bufnr, "modifiable")
    local original_readonly = vim.api.nvim_buf_get_option(bufnr, "readonly")

    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_option(bufnr, "readonly", false)

    -- Using pcall to ensure options are always restored, even on error
    local success, err = pcall(callback)
    if not success then
        utils.log("error", "Failed to modify buffer: " .. tostring(err))
    end

    vim.api.nvim_buf_set_option(bufnr, "modifiable", original_modifiable)
    vim.api.nvim_buf_set_option(bufnr, "readonly", original_readonly)
end

-- 高亮组定义
M.highlights = {
    TITLE = "DoodleTitle",
    SUBTITLE = "DoodleSubtitle",
    STATUS_GENERATING = "DoodleStatusGenerating",
    STATUS_SUCCESS = "DoodleStatusSuccess",
    STATUS_ERROR = "DoodleStatusError",
    BORDER = "DoodleBorder",
    USER_MESSAGE = "DoodleUserMessage",
    ASSISTANT_MESSAGE = "DoodleAssistantMessage",
}

-- 初始化UI模块
function M.init(config)
    M.config = config
    M.ui.status = M.UI_STATUS.CLOSED
    M.setup_highlights()
    utils.log("info", "UI模块初始化完成")
end

-- 设置自定义高亮
function M.setup_highlights()
    local highlights = {
        [M.highlights.TITLE] = { fg = "#61afef", bold = true },
        [M.highlights.SUBTITLE] = { fg = "#98c379" },
        [M.highlights.STATUS_GENERATING] = { fg = "#e5c07b", bg = "#3e4452" },
        [M.highlights.STATUS_SUCCESS] = { fg = "#98c379", bg = "#3e4452" },
        [M.highlights.STATUS_ERROR] = { fg = "#e06c75", bg = "#3e4452" },
        [M.highlights.BORDER] = { fg = "#5c6370" },
        [M.highlights.USER_MESSAGE] = { fg = "#61afef" },
        [M.highlights.ASSISTANT_MESSAGE] = { fg = "#d19a66" },
    }
    
    for name, opts in pairs(highlights) do
        vim.api.nvim_set_hl(0, name, opts)
    end
end

-- 切换UI显示状态
function M.toggle()
    if M.ui.status == M.UI_STATUS.CLOSED then
        M.open()
    else
        M.close()
    end
end

-- 计算容器尺寸
function M.calculate_layout_sizes()
    local vim_width = vim.api.nvim_get_option("columns")
    local sidebar_width = math.floor(vim_width * (M.config.ui.width or 0.35))
    
    return {
        sidebar_width = sidebar_width,
        input_height = "25%",
        status_height = 3,
    }
end

-- 创建状态指示器
function M.create_status_container(relative_winid)
    if M.ui.status_split then
        M.ui.status_split:unmount()
    end
    
    local Split = require("nui.split")
    
    M.ui.status_split = Split({
        relative = {
            type = 'win',
            winid = relative_winid,
        },
        position = 'top',
        size = M.calculate_layout_sizes().status_height,
        enter = false,
        focusable = false,
        border = {
            style = "rounded",
            text = {
                top = " 🤖 状态 ",
                top_align = "center",
            },
        },
        buf_options = {
            modifiable = false,
            readonly = true,
            filetype = "doodle-status",
        },
        win_options = {
            wrap = false,
            number = false,
            relativenumber = false,
            winhighlight = "Normal:Normal,FloatBorder:" .. M.highlights.BORDER,
        },
    })
    
    M.ui.status_buffer = M.ui.status_split.bufnr
    M.render_status()
    return M.ui.status_split
end

-- 渲染状态信息
function M.render_status()
    if not M.ui.status_buffer or not vim.api.nvim_buf_is_valid(M.ui.status_buffer) then
        return
    end
    
    local status_text = ""
    local status_highlight = ""
    
    if M.ui.current_state == M.GENERATE_STATUS.GENERATING then
        status_text = "🔄 正在生成回复..."
        status_highlight = M.highlights.STATUS_GENERATING
    elseif M.ui.current_state == M.GENERATE_STATUS.TOOL_CALLING then
        status_text = "🔧 工具调用中..."
        status_highlight = M.highlights.STATUS_GENERATING
    elseif M.ui.current_state == M.GENERATE_STATUS.SUCCEEDED then
        status_text = "✅ 生成完成"
        status_highlight = M.highlights.STATUS_SUCCESS
    elseif M.ui.current_state == M.GENERATE_STATUS.FAILED then
        status_text = "❌ 生成失败"
        status_highlight = M.highlights.STATUS_ERROR
    else
        status_text = "💭 等待输入..."
        status_highlight = M.highlights.SUBTITLE
    end
    
    M.with_writable_buffer(M.ui.status_buffer, function()
        vim.api.nvim_buf_set_lines(M.ui.status_buffer, 0, -1, false, {
            status_text,
            "",
            "按 Ctrl+H 查看帮助"
        })
    end)
    
    -- 设置高亮
    if status_highlight then
        vim.api.nvim_buf_add_highlight(M.ui.status_buffer, -1, status_highlight, 0, 0, -1)
    end
end

-- 设置状态
function M.set_status(status)
    M.ui.current_state = status
    M.render_status()
end

-- 打开UI
function M.open()
    if M.ui.status == M.UI_STATUS.OPEN then
        return
    end
    
    -- 检查依赖
    local split_ok, Split = pcall(require, "nui.split")
    
    if not split_ok then
        utils.log("error", "nui.nvim 未安装，请先安装依赖")
        vim.notify("错误: nui.nvim 未安装", vim.log.levels.ERROR)
        return
    end
    
    -- 计算布局尺寸
    local sizes = M.calculate_layout_sizes()
    
    -- 1. 创建主窗格 (输出区域)
    M.ui.output_split = Split({
        relative = 'editor',
        position = 'right',
        size = sizes.sidebar_width,
        enter = false,
        focusable = true,
        border = {
            style = M.config.ui.border or "rounded",
            text = { top = " 📖 对话历史 ", top_align = "center" },
        },
        buf_options = {
            modifiable = false,
            readonly = false,
            filetype = "doodle-output",
        },
        win_options = {
            wrap = true,
            linebreak = true,
            number = false,
            relativenumber = false,
            cursorline = false,
            winhighlight = "Normal:Normal,FloatBorder:" .. M.highlights.BORDER,
        },
    })
    M.ui.output_split:mount()
    
    -- 2. 在主窗格底部创建输入窗格
    M.ui.input_split = Split({
        relative = {
            type = 'win',
            winid = M.ui.output_split.winid,
        },
        position = 'bottom',
        size = sizes.input_height,
        enter = true,
        focusable = true,
        border = {
            style = M.config.ui.border or "rounded",
            text = { top = " ✏️ 输入消息 ", top_align = "center" },
        },
        buf_options = {
            modifiable = true,
            filetype = "doodle-input",
        },
        win_options = {
            wrap = true,
            number = false,
            relativenumber = false,
            cursorline = true,
            winhighlight = "Normal:Normal,FloatBorder:" .. M.highlights.BORDER,
        },
    })
    M.ui.input_split:mount()

    -- 3. 在输入窗格顶部创建状态窗格
    M.ui.status_split = M.create_status_container(M.ui.input_split.winid)
    M.ui.status_split:mount()
    
    -- 获取缓冲区
    M.ui.output_buffer = M.ui.output_split.bufnr
    M.ui.input_buffer = M.ui.input_split.bufnr
    
    -- 创建自动命令组
    M.ui.augroup = vim.api.nvim_create_augroup("doodle_ui_" .. os.time(), { clear = true })
    
    -- 设置按键映射
    M.setup_keymaps()
    
    -- 设置自动命令
    M.setup_autocmds()
    
    -- 更新状态
    M.ui.status = M.UI_STATUS.OPEN
    M.set_status(M.GENERATE_STATUS.IDLE)
    
    -- 显示欢迎信息
    M.display_welcome_message()
    
    -- 刷新窗口ID
    M.refresh_winids()
    
    utils.log("info", "UI已打开")
end

-- 刷新窗口ID
function M.refresh_winids()
    M.ui.winids = {}
    if M.ui.output_split and M.ui.output_split.winid then
        table.insert(M.ui.winids, M.ui.output_split.winid)
    end
    if M.ui.input_split and M.ui.input_split.winid then
        table.insert(M.ui.winids, M.ui.input_split.winid)
    end
    if M.ui.status_split and M.ui.status_split.winid then
        table.insert(M.ui.winids, M.ui.status_split.winid)
    end
end

-- 关闭UI
function M.close()
    if M.ui.status == M.UI_STATUS.CLOSED then
        return
    end
    
    -- 清理自动命令组
    if M.ui.augroup then
        vim.api.nvim_del_augroup_by_id(M.ui.augroup)
        M.ui.augroup = nil
    end
    
    -- 卸载UI组件 (按相反顺序)
    if M.ui.status_split then M.ui.status_split:unmount() end
    if M.ui.input_split then M.ui.input_split:unmount() end
    if M.ui.output_split then M.ui.output_split:unmount() end
    
    -- 重置组件
    M.ui.output_split = nil
    M.ui.input_split = nil
    M.ui.status_split = nil
    M.ui.output_buffer = nil
    M.ui.input_buffer = nil
    M.ui.status_buffer = nil
    M.ui.winids = {}
    M.ui.status = M.UI_STATUS.CLOSED
    M.ui.current_state = M.GENERATE_STATUS.IDLE
    
    utils.log("info", "UI已关闭")
end

-- 设置按键映射
function M.setup_keymaps()
    -- 输入窗口按键映射
    if M.ui.input_split then
        local input_opts = { noremap = true, silent = true }
        
        -- 提交输入
        M.ui.input_split:map("i", "<CR>", function()
            M.handle_input_submit()
        end, input_opts)
        
        -- 多行输入
        M.ui.input_split:map("i", "<S-CR>", function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "i", false)
        end, input_opts)
        
        -- 退出插入模式
        M.ui.input_split:map("i", "<Esc>", function()
            vim.cmd("stopinsert")
        end, input_opts)
        
        -- 窗口导航
        M.ui.input_split:map("n", "<Tab>", function()
            M.focus_output()
        end, input_opts)
        
        M.ui.input_split:map("i", "<C-k>", function()
            M.focus_output()
            vim.cmd("stopinsert")
        end, input_opts)
        
        -- 快捷操作
        M.ui.input_split:map("i", "<C-l>", function()
            M.clear_input()
        end, input_opts)
        
        -- 关闭UI
        M.ui.input_split:map("n", "q", function()
            M.close()
        end, input_opts)
        
        M.ui.input_split:map("n", "<Esc>", function()
            M.close()
        end, input_opts)
    end
    
    -- 输出窗口按键映射
    if M.ui.output_split then
        local output_opts = { noremap = true, silent = true }
        
        -- 窗口导航
        M.ui.output_split:map("n", "<Tab>", function()
            M.focus_input()
        end, output_opts)
        
        M.ui.output_split:map("n", "<C-j>", function()
            M.focus_input()
        end, output_opts)
        
        -- 滚动控制
        M.ui.output_split:map("n", "j", function()
            M.ui.scroll_enabled = false
            vim.cmd("normal! j")
        end, output_opts)
        
        M.ui.output_split:map("n", "k", function()
            M.ui.scroll_enabled = false
            vim.cmd("normal! k")
        end, output_opts)
        
        M.ui.output_split:map("n", "G", function()
            M.ui.scroll_enabled = true
            vim.cmd("normal! G")
        end, output_opts)
        
        -- 清空输出
        M.ui.output_split:map("n", "<C-l>", function()
            M.clear_output()
        end, output_opts)
        
        -- 关闭UI
        M.ui.output_split:map("n", "q", function()
            M.close()
        end, output_opts)
        
        M.ui.output_split:map("n", "<Esc>", function()
            M.close()
        end, output_opts)
        
        -- 帮助
        M.ui.output_split:map("n", "<C-h>", function()
            M.show_help()
        end, output_opts)
    end
end

-- 设置自动命令
function M.setup_autocmds()
    if not M.ui.augroup then
        return
    end
    
    -- 输入窗口自动命令
    if M.ui.input_buffer then
        vim.api.nvim_create_autocmd("BufEnter", {
            group = M.ui.augroup,
            buffer = M.ui.input_buffer,
            callback = function()
                if M.config.ui.auto_insert then
                    vim.cmd("startinsert!")
                end
            end,
        })
        
        vim.api.nvim_create_autocmd("BufLeave", {
            group = M.ui.augroup,
            buffer = M.ui.input_buffer,
            callback = function()
                vim.cmd("stopinsert")
            end,
        })
    end
    
    -- 窗口调整
    vim.api.nvim_create_autocmd("VimResized", {
        group = M.ui.augroup,
        callback = function()
            M.adjust_layout()
        end,
    })
end

-- 调整布局
function M.adjust_layout()
    if M.ui.status ~= M.UI_STATUS.OPEN then
        return
    end
    
    -- 重新计算尺寸并调整
    local sizes = M.calculate_layout_sizes()
    
    if M.ui.output_split then
        vim.api.nvim_win_set_width(M.ui.output_split.winid, sizes.sidebar_width)
    end
    if M.ui.input_split then
        -- nui.split 不支持直接调整高度，需要重新创建
        M.close()
        M.open()
    end
end

-- 处理输入提交
function M.handle_input_submit()
    if not M.ui.input_buffer then
        return
    end
    
    -- 获取输入内容
    local lines = vim.api.nvim_buf_get_lines(M.ui.input_buffer, 0, -1, false)
    local input = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")
    
    if input == "" then
        return
    end
    
    -- 清空输入框
    vim.api.nvim_buf_set_lines(M.ui.input_buffer, 0, -1, false, {})
    
    -- 显示用户输入
    M.output("👤 " .. input, { highlight = M.highlights.USER_MESSAGE, prefix = true })
    M.output("")
    
    -- 发送到agent处理
    agent.send_message(input)
    
    -- 切换到输出窗口
    vim.defer_fn(function()
        M.focus_output()
    end, 100)
end

-- 聚焦输入框
function M.focus_input()
    if M.ui.input_split and M.ui.input_split.winid then
        vim.api.nvim_set_current_win(M.ui.input_split.winid)
        if M.config.ui.auto_insert then
            vim.cmd("startinsert!")
        end
    end
end

-- 聚焦输出框
function M.focus_output()
    if M.ui.output_split and M.ui.output_split.winid then
        vim.api.nvim_set_current_win(M.ui.output_split.winid)
        if M.ui.scroll_enabled then
            M.scroll_to_bottom()
        end
    end
end

-- 输出文本到UI
function M.output(text, opts)
    if M.ui.status ~= M.UI_STATUS.OPEN or not M.ui.output_buffer then
        return
    end
    
    opts = opts or {}
    local highlight = opts.highlight
    local prefix = opts.prefix and "  " or ""
    
    -- 处理多行文本
    local lines = {}
    for line in text:gmatch("[^\r\n]*") do
        table.insert(lines, prefix .. line)
    end
    
    if #lines == 0 then
        lines = { prefix .. text }
    end
    
    -- 添加到输出缓冲区
    local current_lines = vim.api.nvim_buf_get_lines(M.ui.output_buffer, 0, -1, false)
    local start_line = #current_lines
    
    for _, line in ipairs(lines) do
        table.insert(current_lines, line)
    end
    
    M.with_writable_buffer(M.ui.output_buffer, function()
        vim.api.nvim_buf_set_lines(M.ui.output_buffer, 0, -1, false, current_lines)
    end)
    
    -- 应用高亮
    if highlight then
        for i, _ in ipairs(lines) do
            vim.api.nvim_buf_add_highlight(M.ui.output_buffer, -1, highlight, start_line + i, 0, -1)
        end
    end
    
    -- 滚动到底部
    if M.ui.scroll_enabled then
        M.scroll_to_bottom()
    end
end

-- 追加文本到最后一行
function M.append(text, opts)
    if M.ui.status ~= M.UI_STATUS.OPEN or not M.ui.output_buffer then
        return
    end
    
    opts = opts or {}
    local highlight = opts.highlight
    
    local current_lines = vim.api.nvim_buf_get_lines(M.ui.output_buffer, 0, -1, false)
    if #current_lines == 0 then
        current_lines = {""}
    end
    
    local last_line_idx = #current_lines - 1
    local old_content = current_lines[#current_lines]
    current_lines[#current_lines] = old_content .. text
    
    M.with_writable_buffer(M.ui.output_buffer, function()
        vim.api.nvim_buf_set_lines(M.ui.output_buffer, 0, -1, false, current_lines)
    end)
    
    -- 应用高亮
    if highlight then
        vim.api.nvim_buf_add_highlight(M.ui.output_buffer, -1, highlight, last_line_idx, #old_content, -1)
    end
    
    -- 滚动到底部
    if M.ui.scroll_enabled then
        M.scroll_to_bottom()
    end
end

-- 滚动到底部
function M.scroll_to_bottom()
    if not M.ui.output_split or not M.ui.output_split.winid then
        return
    end
    
    vim.schedule(function()
        if vim.api.nvim_win_is_valid(M.ui.output_split.winid) then
            local line_count = vim.api.nvim_buf_line_count(M.ui.output_buffer)
            vim.api.nvim_win_set_cursor(M.ui.output_split.winid, { line_count, 0 })
        end
    end)
end

-- 清空输出
function M.clear_output()
    if not M.ui.output_buffer then
        return
    end
    
    M.with_writable_buffer(M.ui.output_buffer, function()
        vim.api.nvim_buf_set_lines(M.ui.output_buffer, 0, -1, false, {})
    end)
    
    -- 重新显示欢迎信息
    M.display_welcome_message()
end

-- 清空输入
function M.clear_input()
    if M.ui.input_buffer then
        vim.api.nvim_buf_set_lines(M.ui.input_buffer, 0, -1, false, {})
    end
end

-- 显示帮助信息
function M.show_help()
    local help_lines = {
        "",
        "📚 Doodle.nvim 帮助信息",
        string.rep("=", 50),
        "",
        "🎯 基本操作:",
        "  • 在输入框中输入问题，按 Enter 提交",
        "  • 使用 Shift+Enter 进行多行输入",
        "  • 按 Tab 在输入框和输出框之间切换",
        "",
        "⌨️  快捷键说明:",
        "",
        "  📝 输入框操作:",
        "    Enter       提交消息",
        "    Shift+Enter 换行（多行输入）",
        "    Ctrl+K      切换到输出框",
        "    Ctrl+L      清空输入",
        "    Esc         退出插入模式",
        "",
        "  📖 输出框操作:",
        "    Ctrl+J      切换到输入框",
        "    Ctrl+L      清空输出",
        "    Ctrl+H      显示此帮助",
        "    j/k         逐行滚动",
        "    G           跳到底部并启用自动滚动",
        "",
        "  🚪 通用操作:",
        "    q           关闭侧边栏",
        "    Esc         关闭侧边栏",
        "",
        "🔄 状态指示器:",
        "  💭 等待输入     - 准备接收新消息",
        "  🔄 正在生成     - AI正在处理请求",
        "  🔧 工具调用     - AI正在使用工具",
        "  ✅ 生成完成     - 消息处理完成",
        "  ❌ 生成失败     - 处理过程中出错",
        "",
        "💡 小贴士:",
        "  • 滚动时会暂停自动滚动，按 G 重新启用",
        "  • 使用 Ctrl+L 可以快速清空对话历史",
        "  • 输入框支持多行文本编辑",
        "",
        string.rep("=", 50),
        ""
    }
    
    for _, line in ipairs(help_lines) do
        M.output(line, { highlight = M.highlights.SUBTITLE })
    end
end

-- 显示欢迎信息
function M.display_welcome_message()
    local welcome_lines = {
        "",
        "🎨 欢迎使用 Doodle.nvim!",
        string.rep("=", 50),
        "",
        "✨ 功能特性:",
        "  • 🤖 智能AI对话助手",
        "  • 📝 多行输入支持",
        "  • 🎯 实时状态指示",
        "  • ⌨️  直观的快捷键",
        "  • 🎨 美观的界面设计",
        "",
        "🚀 开始使用:",
        "  1. 在下方输入框中输入你的问题",
        "  2. 按 Enter 提交消息",
        "  3. 在输出区域查看AI回复",
        "",
        "💡 需要帮助？按 Ctrl+H 查看详细帮助",
        "",
        string.rep("=", 50),
        ""
    }
    
    for _, line in ipairs(welcome_lines) do
        M.output(line, { highlight = M.highlights.TITLE })
    end
end

-- 显示生成中的消息
function M.output_generating(text)
    M.output("🤖 " .. text, { highlight = M.highlights.ASSISTANT_MESSAGE })
end

-- 显示错误消息
function M.output_error(text)
    M.output("❌ 错误: " .. text, { highlight = M.highlights.STATUS_ERROR })
    M.set_status(M.GENERATE_STATUS.FAILED)
end

-- 显示成功消息
function M.output_success(text)
    M.output("✅ " .. text, { highlight = M.highlights.STATUS_SUCCESS })
    M.set_status(M.GENERATE_STATUS.SUCCEEDED)
end

-- 检查UI状态
function M.is_open()
    return M.ui.status == M.UI_STATUS.OPEN
end

-- 检查是否正在生成
function M.is_generating()
    return M.ui.current_state == M.GENERATE_STATUS.GENERATING or 
           M.ui.current_state == M.GENERATE_STATUS.TOOL_CALLING
end

-- 获取UI配置
function M.get_config()
    return M.config
end

-- 设置UI配置
function M.set_config(config)
    M.config = config
    if M.ui.status == M.UI_STATUS.OPEN then
        M.setup_highlights()
    end
end

-- 重新加载UI
function M.reload()
    if M.ui.status == M.UI_STATUS.OPEN then
        M.close()
        M.open()
    end
end

-- 最小化UI
function M.minimize()
    if M.ui.status == M.UI_STATUS.OPEN then
        M.close()
        M.ui.status = M.UI_STATUS.MINIMIZED
    end
end

-- 恢复UI
function M.restore()
    if M.ui.status == M.UI_STATUS.MINIMIZED then
        M.ui.status = M.UI_STATUS.CLOSED
        M.open()
    end
end

-- 获取当前输入内容
function M.get_input()
    if not M.ui.input_buffer then
        return ""
    end
    
    local lines = vim.api.nvim_buf_get_lines(M.ui.input_buffer, 0, -1, false)
    return table.concat(lines, "\n")
end

-- 设置输入内容
function M.set_input(text)
    if not M.ui.input_buffer then
        return
    end
    
    local lines = vim.split(text, "\n")
    vim.api.nvim_buf_set_lines(M.ui.input_buffer, 0, -1, false, lines)
end

-- 获取输出内容
function M.get_output()
    if not M.ui.output_buffer then
        return ""
    end
    
    local lines = vim.api.nvim_buf_get_lines(M.ui.output_buffer, 0, -1, false)
    return table.concat(lines, "\n")
end

-- 调整sidebar宽度
function M.resize_sidebar(width)
    if M.ui.status ~= M.UI_STATUS.OPEN then
        return
    end
    
    -- 保存新的宽度配置
    M.config.ui.width = width
    
    -- 重新打开UI以应用新尺寸
    M.close()
    M.open()
end

-- 获取当前状态
function M.get_current_state()
    return M.ui.current_state
end

-- 获取窗口ID列表
function M.get_winids()
    return M.ui.winids
end

-- 检查窗口是否有效
function M.is_valid_window(winid)
    return winid and vim.api.nvim_win_is_valid(winid)
end

-- 更新配置中的auto_insert设置
function M.set_auto_insert(enabled)
    if M.config and M.config.ui then
        M.config.ui.auto_insert = enabled
    end
end

-- Agent回调函数：处理开始生成
function M.on_generate_start()
    M.set_status(M.GENERATE_STATUS.GENERATING)
    M.output_generating("开始生成回复...")
end

-- Agent回调函数：处理生成完成
function M.on_generate_complete()
    M.set_status(M.GENERATE_STATUS.SUCCEEDED)
    vim.defer_fn(function()
        M.set_status(M.GENERATE_STATUS.IDLE)
    end, 2000)
end

-- Agent回调函数：处理生成失败
function M.on_generate_error(error_msg)
    M.output_error(error_msg or "生成过程中发生未知错误")
    vim.defer_fn(function()
        M.set_status(M.GENERATE_STATUS.IDLE)
    end, 3000)
end

-- Agent回调函数：处理工具调用
function M.on_tool_calling(tool_name)
    M.set_status(M.GENERATE_STATUS.TOOL_CALLING)
    M.output("🔧 正在调用工具: " .. (tool_name or "未知工具"), { highlight = M.highlights.STATUS_GENERATING })
end

-- 导出模块
return M 