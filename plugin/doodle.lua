-- plugin/doodle.lua
-- Doodle.nvim 插件加载文件

-- 避免重复加载
if vim.g.loaded_doodle then
    return
end
vim.g.loaded_doodle = true

-- 检查Neovim版本
if vim.fn.has("nvim-0.8") == 0 then
    vim.notify("Doodle.nvim 需要 Neovim 0.8 或更高版本", vim.log.levels.ERROR)
    return
end

-- 自动初始化函数
local function ensure_initialized()
    if not vim.g.doodle_initialized then
        require("doodle").setup({})
        vim.g.doodle_initialized = true
    end
end

-- 主要命令：打开/关闭Doodle侧边栏
vim.api.nvim_create_user_command("Doodle", function()
    ensure_initialized()
    require("doodle.ui").toggle()
end, {
    desc = "打开/关闭 Doodle.nvim 侧边栏"
})

-- 打开Doodle
vim.api.nvim_create_user_command("DoodleOpen", function()
    ensure_initialized()
    require("doodle.ui").open()
end, {
    desc = "打开 Doodle.nvim 侧边栏"
})

-- 关闭Doodle
vim.api.nvim_create_user_command("DoodleClose", function()
    ensure_initialized()
    require("doodle.ui").close()
end, {
    desc = "关闭 Doodle.nvim 侧边栏"
})

-- 停止当前Agent
vim.api.nvim_create_user_command("DoodleStop", function()
    ensure_initialized()
    local agent = require("doodle.agent")
    if agent.stop() then
        vim.notify("Agent已停止", vim.log.levels.INFO)
    else
        vim.notify("当前没有运行的Agent", vim.log.levels.WARN)
    end
end, {
    desc = "停止当前运行的Agent"
})

-- 暂停当前Agent
vim.api.nvim_create_user_command("DoodlePause", function()
    ensure_initialized()
    local agent = require("doodle.agent")
    if agent.pause() then
        vim.notify("Agent已暂停", vim.log.levels.INFO)
    else
        vim.notify("无法暂停Agent", vim.log.levels.WARN)
    end
end, {
    desc = "暂停当前运行的Agent"
})

-- 恢复当前Agent
vim.api.nvim_create_user_command("DoodleResume", function()
    ensure_initialized()
    local agent = require("doodle.agent")
    if agent.resume() then
        vim.notify("Agent已恢复", vim.log.levels.INFO)
    else
        vim.notify("无法恢复Agent", vim.log.levels.WARN)
    end
end, {
    desc = "恢复当前暂停的Agent"
})

-- 显示Agent状态
vim.api.nvim_create_user_command("DoodleStatus", function()
    ensure_initialized()
    local agent = require("doodle.agent")
    local status = agent.get_status()
    
    if status then
        local info = {
            "Agent状态: " .. status.status,
            "任务ID: " .. (status.current_task_id or "无"),
            "上下文ID: " .. (status.current_context_id or "无"),
            "循环运行: " .. (status.loop_running and "是" or "否"),
            "创建时间: " .. os.date("%Y-%m-%d %H:%M:%S", status.created_at)
        }
        
        vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
    else
        vim.notify("当前没有运行的Agent", vim.log.levels.WARN)
    end
end, {
    desc = "显示当前Agent状态"
})

-- 显示任务进度
vim.api.nvim_create_user_command("DoodleProgress", function()
    ensure_initialized()
    local agent = require("doodle.agent")
    local progress = agent.get_progress()
    local details = agent.get_task_details()
    
    if details then
        local info = {
            "任务进度: " .. string.format("%.1f%%", progress * 100),
            "任务描述: " .. details.description,
            "总共Todo: " .. details.summary.total_todos,
            "已完成: " .. details.summary.completed_todos,
            "待处理: " .. details.summary.pending_todos,
            "任务状态: " .. details.status
        }
        
        vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
    else
        vim.notify("当前没有运行的任务", vim.log.levels.WARN)
    end
end, {
    desc = "显示当前任务进度"
})

-- 列出所有可用的工具
vim.api.nvim_create_user_command("DoodleTools", function()
    ensure_initialized()
    local tool = require("doodle.tool")
    local tools = tool.list_tools()
    
    local info = {"可用工具:"}
    for _, t in ipairs(tools) do
        table.insert(info, "  • " .. t.name .. ": " .. t.description)
    end
    
    vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end, {
    desc = "列出所有可用的工具"
})

-- 列出所有可用的Provider
vim.api.nvim_create_user_command("DoodleProviders", function()
    ensure_initialized()
    local provider = require("doodle.provider")
    local providers = provider.list_providers()
    
    local info = {"可用Provider:"}
    for _, p in ipairs(providers) do
        local status = p.stream and "流式" or "非流式"
        local functions = p.supports_functions and "支持函数" or "不支持函数"
        table.insert(info, "  • " .. p.name .. " (" .. p.model .. ") - " .. status .. ", " .. functions)
    end
    
    vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
end, {
    desc = "列出所有可用的Provider"
})

-- 切换Provider
vim.api.nvim_create_user_command("DoodleSetProvider", function(opts)
    ensure_initialized()
    local provider_name = opts.args
    if not provider_name or provider_name == "" then
        vim.notify("请指定Provider名称", vim.log.levels.ERROR)
        return
    end
    
    local provider = require("doodle.provider")
    if provider.set_current_provider(provider_name) then
        vim.notify("已切换到Provider: " .. provider_name, vim.log.levels.INFO)
    else
        vim.notify("Provider不存在: " .. provider_name, vim.log.levels.ERROR)
    end
end, {
    nargs = 1,
    desc = "切换到指定的Provider",
    complete = function()
        local provider = require("doodle.provider")
        local providers = provider.list_providers()
        local names = {}
        for _, p in ipairs(providers) do
            table.insert(names, p.name)
        end
        return names
    end
})

-- 重新加载配置
vim.api.nvim_create_user_command("DoodleReload", function()
    local doodle = require("doodle")
    
    -- 清理现有资源
    require("doodle.agent").cleanup()
    require("doodle.ui").close()
    
    -- 重新加载配置
    local config = doodle.get_config()
    doodle.setup(config)
    
    vim.notify("Doodle.nvim 已重新加载", vim.log.levels.INFO)
end, {
    desc = "重新加载 Doodle.nvim 配置"
})

-- 清理资源
vim.api.nvim_create_user_command("DoodleCleanup", function()
    ensure_initialized()
    local agent = require("doodle.agent")
    local task = require("doodle.task")
    
    agent.cleanup()
    task.cleanup_completed_tasks()
    
    vim.notify("Doodle.nvim 资源已清理", vim.log.levels.INFO)
end, {
    desc = "清理 Doodle.nvim 资源"
})

-- 显示帮助信息
vim.api.nvim_create_user_command("DoodleHelp", function()
    local help_info = {
        "🎨 Doodle.nvim 帮助",
        "",
        "📝 主要命令:",
        "  :Doodle          - 打开/关闭侧边栏",
        "  :DoodleOpen      - 打开侧边栏",
        "  :DoodleClose     - 关闭侧边栏",
        "",
        "🤖 Agent控制:",
        "  :DoodleStop      - 停止当前Agent",
        "  :DoodlePause     - 暂停当前Agent", 
        "  :DoodleResume    - 恢复当前Agent",
        "  :DoodleStatus    - 显示Agent状态",
        "  :DoodleProgress  - 显示任务进度",
        "",
        "🔧 工具与Provider:",
        "  :DoodleTools     - 列出所有工具",
        "  :DoodleProviders - 列出所有Provider",
        "  :DoodleSetProvider <name> - 切换Provider",
        "",
        "⚙️  系统命令:",
        "  :DoodleReload    - 重新加载配置",
        "  :DoodleCleanup   - 清理资源",
        "  :DoodleHelp      - 显示此帮助",
        "",
        "💡 快捷键（在输入框中）:",
        "  <Enter>   - 提交查询",
        "  <Ctrl-C>  - 取消任务",
        "  <Ctrl-D>  - 关闭界面",
        "  <Ctrl-L>  - 清空输出",
        "  <Ctrl-P>  - 暂停/恢复",
        "",
        "📖 更多信息请查看 GitHub 仓库"
    }
    
    vim.notify(table.concat(help_info, "\n"), vim.log.levels.INFO)
end, {
    desc = "显示 Doodle.nvim 帮助信息"
})

-- 设置全局快捷键（可选）
vim.keymap.set("n", "<leader>dd", function()
    require("doodle.ui").toggle()
end, { desc = "打开/关闭 Doodle.nvim" })

vim.keymap.set("n", "<leader>ds", function()
    require("doodle.agent").stop()
end, { desc = "停止 Doodle Agent" })

vim.keymap.set("n", "<leader>dp", function()
    require("doodle.agent").pause()
end, { desc = "暂停 Doodle Agent" })

vim.keymap.set("n", "<leader>dr", function()
    require("doodle.agent").resume()
end, { desc = "恢复 Doodle Agent" })

-- 创建自动命令组
local doodle_group = vim.api.nvim_create_augroup("Doodle", { clear = true })

-- 当插件卸载时清理资源
vim.api.nvim_create_autocmd("VimLeave", {
    group = doodle_group,
    callback = function()
        require("doodle.agent").cleanup()
        require("doodle.ui").close()
    end,
    desc = "清理 Doodle.nvim 资源"
})

-- 定期触发状态更新事件
vim.api.nvim_create_autocmd("User", {
    group = doodle_group,
    pattern = "DoodleStatusUpdate",
    callback = function()
        -- 这里可以添加状态更新逻辑
    end,
    desc = "Doodle.nvim 状态更新"
})

-- 创建定时器定期触发状态更新
local timer = vim.loop.new_timer()
timer:start(0, 1000, vim.schedule_wrap(function()
    vim.api.nvim_exec_autocmds("User", { pattern = "DoodleStatusUpdate" })
end))

-- 当退出时停止定时器
vim.api.nvim_create_autocmd("VimLeave", {
    group = doodle_group,
    callback = function()
        if timer then
            timer:stop()
            timer:close()
        end
    end,
    desc = "停止 Doodle.nvim 定时器"
})

-- 插件加载完成标志
vim.g.loaded_doodle = true 