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

-- UI组件
M.ui = {
    status = M.UI_STATUS.CLOSED,
    layout = nil,           -- 主要的layout容器
    output_popup = nil,     -- 输出组件（上面70%）
    input_popup = nil,      -- 输入组件（下面30%）
    output_buffer = nil,
    input_buffer = nil,
    output_lines = {},
    last_append_line = nil
}

-- 初始化UI模块
function M.init(config)
    M.config = config
    M.ui.status = M.UI_STATUS.CLOSED
    utils.log("info", "UI模块初始化完成")
end

-- 切换UI显示状态
function M.toggle()
    if M.ui.status == M.UI_STATUS.CLOSED then
        M.open()
    else
        M.close()
    end
end

-- 打开UI
function M.open()
    if M.ui.status == M.UI_STATUS.OPEN then
        return
    end
    
    -- 检查依赖 - 检查实际使用的组件
    local layout_ok, Layout = pcall(require, "nui.layout")
    local popup_ok, Popup = pcall(require, "nui.split")
    
    if not layout_ok or not popup_ok then
        utils.log("error", "nui.nvim 未安装，请先安装依赖")
        vim.notify("错误: nui.nvim 未安装", vim.log.levels.ERROR)
        return
    end
    
    -- 计算sidebar尺寸
    local vim_width = vim.api.nvim_get_option("columns")
    local vim_height = vim.api.nvim_get_option("lines")
    local sidebar_width = math.floor(vim_width * (M.config.ui.width or 0.3))  -- 默认30%宽度
    
    -- 创建输出窗口（上面70%）
    M.ui.output_popup = Popup({
        enter = false,
        focusable = true,
        border = {
            style = M.config.ui.border or "rounded",
            text = {
                top = " 🤖 输出 ",
                top_align = "center",
            },
        },
        buf_options = {
            modifiable = false,
            readonly = true,
            filetype = "doodle-output",
        },
        win_options = {
            wrap = true,
            linebreak = true,
            number = false,
            relativenumber = false,
            cursorline = false,
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
    })
    
    -- 创建输入窗口（下面30%）
    M.ui.input_popup = Popup({
        enter = true,
        focusable = true,
        border = {
            style = M.config.ui.border or "rounded",
            text = {
                top = " 💬 输入 ",
                top_align = "center",
            },
        },
        buf_options = {
            modifiable = true,
            filetype = "doodle-input",
        },
        win_options = {
            wrap = false,
            number = false,
            relativenumber = false,
            cursorline = true,
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
        },
    })
    
    -- 创建右侧sidebar布局（两个组件垂直排列，7:3比例）
    M.ui.layout = Layout(
        {
            position = "right",
            size = {
                width = sidebar_width,
                height = "90%",  -- 留一些边距
            },
        },
        Layout.Box({
            Layout.Box(M.ui.output_popup, { size = "70%" }),  -- 输出区域占70%
            Layout.Box(M.ui.input_popup, { size = "30%" }),   -- 输入区域占30%
        }, { dir = "col" })  -- 垂直方向排列
    )
    
    -- 挂载UI
    M.ui.layout:mount()
    
    -- 获取缓冲区
    M.ui.output_buffer = M.ui.output_popup.bufnr
    M.ui.input_buffer = M.ui.input_popup.bufnr
    
    -- 设置按键映射
    M.setup_input_mappings()
    M.setup_output_mappings()
    M.setup_global_mappings()
    
    -- 更新状态
    M.ui.status = M.UI_STATUS.OPEN
    
    -- 显示欢迎信息
    M.display_welcome_message()
    
    utils.log("info", "UI已打开")
end

-- 关闭UI
function M.close()
    if M.ui.status == M.UI_STATUS.CLOSED then
        return
    end
    
    -- 卸载UI组件
    if M.ui.layout then
        M.ui.layout:unmount()
        M.ui.layout = nil
    end
    
    -- 重置组件
    M.ui.output_popup = nil
    M.ui.input_popup = nil
    M.ui.output_buffer = nil
    M.ui.input_buffer = nil
    M.ui.status = M.UI_STATUS.CLOSED
    
    utils.log("info", "UI已关闭")
end

-- 设置输入框按键映射
function M.setup_input_mappings()
    if not M.ui.input_popup then
        return
    end
    
    local map_options = { noremap = true, silent = true }
    
    -- 提交输入 (Enter)
    M.ui.input_popup:map("i", "<CR>", function()
        M.handle_input_submit()
    end, map_options)
    
    -- 退出输入模式 (Escape)
    M.ui.input_popup:map("i", "<Esc>", function()
        vim.cmd("stopinsert")
    end, map_options)
    
    -- 关闭UI (Escape in normal mode)
    M.ui.input_popup:map("n", "<Esc>", function()
        M.close()
    end, map_options)
    
    -- 关闭UI (q in normal mode)
    M.ui.input_popup:map("n", "q", function()
        M.close()
    end, map_options)
    
    -- 切换到输出窗口 (Tab)
    M.ui.input_popup:map("n", "<Tab>", function()
        M.focus_output()
    end, map_options)
    
    M.ui.input_popup:map("i", "<C-k>", function()
        M.focus_output()
    end, map_options)
    
    -- 清空输入 (Ctrl+L)
    M.ui.input_popup:map("i", "<C-l>", function()
        M.clear_input()
    end, map_options)
    
    -- 历史记录导航
    M.ui.input_popup:map("i", "<Up>", function()
        M.navigate_history(-1)
    end, map_options)
    
    M.ui.input_popup:map("i", "<Down>", function()
        M.navigate_history(1)
    end, map_options)
end

-- 设置输出框按键映射
function M.setup_output_mappings()
    if not M.ui.output_popup then
        return
    end
    
    local map_options = { noremap = true, silent = true }
    
    -- 关闭UI (Escape)
    M.ui.output_popup:map("n", "<Esc>", function()
        M.close()
    end, map_options)
    
    -- 关闭UI (q)
    M.ui.output_popup:map("n", "q", function()
        M.close()
    end, map_options)
    
    -- 切换到输入窗口 (Tab)
    M.ui.output_popup:map("n", "<Tab>", function()
        M.focus_input()
    end, map_options)
    
    M.ui.output_popup:map("n", "<C-j>", function()
        M.focus_input()
    end, map_options)
    
    -- 清空输出 (Ctrl+L)
    M.ui.output_popup:map("n", "<C-l>", function()
        M.clear_output()
    end, map_options)
    
    -- 滚动
    M.ui.output_popup:map("n", "j", function()
        vim.cmd("normal! j")
    end, map_options)
    
    M.ui.output_popup:map("n", "k", function()
        vim.cmd("normal! k")
    end, map_options)
    
    M.ui.output_popup:map("n", "<C-d>", function()
        vim.cmd("normal! \\<C-d>")
    end, map_options)
    
    M.ui.output_popup:map("n", "<C-u>", function()
        vim.cmd("normal! \\<C-u>")
    end, map_options)
end

-- 设置全局按键映射
function M.setup_global_mappings()
    -- 在布局级别设置一些全局快捷键
    if M.ui.layout then
        -- 这里可以添加一些全局的布局快捷键
    end
end

-- 处理输入提交
function M.handle_input_submit()
    if not M.ui.input_buffer then
        return
    end
    
    -- 获取输入内容
    local lines = vim.api.nvim_buf_get_lines(M.ui.input_buffer, 0, -1, false)
    local input = table.concat(lines, "\n"):gsub("^%s*(.-)%s*$", "%1")  -- 去除首尾空白
    
    -- 检查输入是否为空
    if input == "" then
        return
    end
    
    -- 清空输入框
    vim.api.nvim_buf_set_lines(M.ui.input_buffer, 0, -1, false, {})
    
    -- 显示用户输入
    M.output("👤 用户: " .. input, { color = "blue" })
    M.output("")  -- 空行分隔
    
    -- 发送到agent处理
    agent.send_message(input)
    
    -- 自动切换焦点到输出窗口
    vim.defer_fn(function()
        M.focus_output()
    end, 100)
end

-- 历史记录导航
function M.navigate_history(direction)
    -- TODO: 实现历史记录导航
    -- 这里可以添加历史记录功能
    utils.log("debug", "历史记录导航: " .. direction)
end

-- 聚焦输入框
function M.focus_input()
    if M.ui.input_popup and M.ui.input_popup.winid then
        vim.api.nvim_set_current_win(M.ui.input_popup.winid)
        vim.cmd("startinsert!")  -- 进入插入模式，并移动到行尾
    end
end

-- 聚焦输出框
function M.focus_output()
    if M.ui.output_popup and M.ui.output_popup.winid then
        vim.api.nvim_set_current_win(M.ui.output_popup.winid)
        -- 滚动到底部
        M.scroll_to_bottom()
    end
end

-- 输出文本到UI
function M.output(text, opts)
    if M.ui.status ~= M.UI_STATUS.OPEN or not M.ui.output_buffer then
        return
    end
    
    opts = opts or {}
    local color = opts.color or "white"
    local prefix = opts.prefix or ""
    
    -- 处理多行文本
    local lines = {}
    for line in text:gmatch("[^\r\n]*") do
        if line ~= "" then  -- 跳过空字符串，但保留空行
            table.insert(lines, prefix .. line)
        else
            table.insert(lines, "")
        end
    end
    
    if #lines == 0 then
        lines = { prefix .. text }
    end
    
    -- 添加到输出缓冲区
    local current_lines = vim.api.nvim_buf_get_lines(M.ui.output_buffer, 0, -1, false)
    for _, line in ipairs(lines) do
        table.insert(current_lines, line)
    end
    
    -- 临时设置为可修改
    vim.api.nvim_buf_set_option(M.ui.output_buffer, "modifiable", true)
    vim.api.nvim_buf_set_lines(M.ui.output_buffer, 0, -1, false, current_lines)
    vim.api.nvim_buf_set_option(M.ui.output_buffer, "modifiable", false)
    
    -- 滚动到底部
    M.scroll_to_bottom()
end

-- 追加文本到最后一行
function M.append(text)
    if M.ui.status ~= M.UI_STATUS.OPEN or not M.ui.output_buffer then
        return
    end
    
    local current_lines = vim.api.nvim_buf_get_lines(M.ui.output_buffer, 0, -1, false)
    if #current_lines == 0 then
        current_lines = {""}
    end
    
    -- 追加到最后一行
    current_lines[#current_lines] = current_lines[#current_lines] .. text
    
    -- 临时设置为可修改
    vim.api.nvim_buf_set_option(M.ui.output_buffer, "modifiable", true)
    vim.api.nvim_buf_set_lines(M.ui.output_buffer, 0, -1, false, current_lines)
    vim.api.nvim_buf_set_option(M.ui.output_buffer, "modifiable", false)
    
    -- 滚动到底部
    M.scroll_to_bottom()
end

-- 滚动到底部
function M.scroll_to_bottom()
    if M.ui.output_popup and M.ui.output_popup.winid then
        vim.api.nvim_buf_call(M.ui.output_buffer, function()
            vim.api.nvim_win_set_cursor(M.ui.output_popup.winid, { vim.fn.line('$'), 0 })
        end)
    end
end

-- 清空输出
function M.clear_output()
    if M.ui.output_buffer then
        vim.api.nvim_buf_set_option(M.ui.output_buffer, "modifiable", true)
        vim.api.nvim_buf_set_lines(M.ui.output_buffer, 0, -1, false, {})
        vim.api.nvim_buf_set_option(M.ui.output_buffer, "modifiable", false)
        M.ui.output_lines = {}
        
        -- 重新显示欢迎信息
        M.display_welcome_message()
    end
end

-- 清空输入
function M.clear_input()
    if M.ui.input_buffer then
        vim.api.nvim_buf_set_lines(M.ui.input_buffer, 0, -1, false, {})
    end
end

-- 显示欢迎信息
function M.display_welcome_message()
    local welcome_lines = {
        "🎨 欢迎使用 Doodle.nvim!",
        "",
        "💡 快捷键说明:",
        "  📝 输入窗口:",
        "    <Enter>     提交问题", 
        "    <Esc>       退出输入模式",
        "    <Tab>       切换到输出窗口",
        "    <Ctrl-K>    切换到输出窗口",
        "    <Ctrl-L>    清空输入",
        "    <Up/Down>   历史记录导航",
        "",
        "  📖 输出窗口:",
        "    <Tab>       切换到输入窗口",
        "    <Ctrl-J>    切换到输入窗口", 
        "    <Ctrl-L>    清空输出",
        "    j/k         上下滚动",
        "    <Ctrl-D/U>  快速滚动",
        "",
        "  🚪 全局:",
        "    <Esc>       关闭UI",
        "    q           关闭UI",
        "",
        "🚀 请在下方输入您的问题...",
        "=" .. string.rep("=", 50),
        ""
    }
    
    for _, line in ipairs(welcome_lines) do
        M.output(line)
    end
end

-- 检查UI状态
function M.is_open()
    return M.ui.status == M.UI_STATUS.OPEN
end

-- 获取UI配置
function M.get_config()
    return M.config
end

-- 设置UI配置
function M.set_config(config)
    M.config = config
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
    
    local lines = {}
    for line in text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    
    if #lines == 0 then
        lines = { text }
    end
    
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

-- 导出模块
return M 