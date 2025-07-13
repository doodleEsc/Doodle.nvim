-- lua/doodle/agent.lua
local utils = require("doodle.utils")
local task = require("doodle.task")
local context = require("doodle.context")
local prompt = require("doodle.prompt")
local tool = require("doodle.tool")
local provider = require("doodle.provider")
local M = {}

-- Agent 状态
M.AGENT_STATUS = {
    IDLE = "idle",
    THINKING = "thinking",
    WORKING = "working",
    PAUSED = "paused",
    STOPPED = "stopped"
}

-- Agent 实例
M.current_agent = nil

-- Agent 类
local Agent = {}
Agent.__index = Agent

-- 创建新的Agent实例
function Agent.new(callbacks)
    local self = setmetatable({}, Agent)
    
    self.id = utils.generate_uuid()
    self.status = M.AGENT_STATUS.IDLE
    self.callbacks = callbacks or {}
    self.current_task_id = nil
    self.current_context_id = nil
    self.loop_running = false
    self.stop_requested = false
    self.created_at = utils.get_timestamp()
    
    return self
end

-- 启动Agent
function Agent:start(query, callbacks)
    if self.status ~= M.AGENT_STATUS.IDLE then
        utils.log("warn", "Agent已经在运行中")
        return false
    end
    
    -- 更新回调函数
    if callbacks then
        self.callbacks = callbacks
    end
    
    utils.log("info", "Agent启动，处理查询: " .. query)
    
    -- 创建上下文
    self.current_context_id = "context_" .. utils.generate_uuid()
    
    -- 获取上下文变量
    local context_vars = prompt.get_context_variables()
    
    -- 创建系统消息
    local system_message = prompt.create_system_message(context_vars)
    context.create_context(self.current_context_id, system_message.content)
    
    -- 添加用户消息
    context.add_user_message(self.current_context_id, query)
    
    -- 开始思考阶段
    self:think_task(query)
    
    return true
end

-- 思考任务阶段
function Agent:think_task(query)
    self.status = M.AGENT_STATUS.THINKING
    self:output("🤔 正在分析您的请求...")
    
    -- 准备think_task工具调用
    local think_prompt_vars = prompt.get_context_variables()
    think_prompt_vars.user_query = query
    
    local think_message = prompt.render("think_task", think_prompt_vars)
    
    -- 添加think_task消息到上下文
    context.add_user_message(self.current_context_id, think_message)
    
    -- 获取可用工具列表
    local available_tools = tool.get_all_function_call_formats()
    
    -- 调用Provider
    local messages = context.get_formatted_messages(self.current_context_id)
    local options = {
        stream = true,
        tools = available_tools,
        max_tokens = 2048
    }
    
    local response_buffer = ""
    local function_call_buffer = {}
    
    provider.request(messages, options, function(content, meta)
        if meta and meta.error then
            self:output("❌ 错误: " .. (meta.error or "未知错误"))
            self:stop()
            return
        end
        
        if meta and meta.done then
            -- 处理完整的响应
            if #function_call_buffer > 0 then
                self:handle_function_calls(function_call_buffer)
            elseif response_buffer ~= "" then
                context.add_assistant_message(self.current_context_id, response_buffer)
                self:output("💡 " .. response_buffer)
            end
            return
        end
        
        if meta and meta.type == "content" and content then
            response_buffer = response_buffer .. content
            self:output(content, { append = true })
        elseif meta and meta.type == "function_call" and content then
            table.insert(function_call_buffer, content)
        end
    end)
end

-- 处理函数调用
function Agent:handle_function_calls(function_calls)
    for _, func_call in ipairs(function_calls) do
        local tool_name = func_call.name
        local arguments = func_call.arguments
        
        -- 解析参数
        local success, parsed_args = pcall(vim.json.decode, arguments)
        if success then
            utils.log("info", "执行工具: " .. tool_name)
            self:output("🔧 执行工具: " .. tool_name)
            
            -- 执行工具
            local result = tool.execute_tool(tool_name, parsed_args)
            
            -- 添加工具消息到上下文
            context.add_tool_message(self.current_context_id, tool_name, func_call.call_id or utils.generate_uuid(), vim.json.encode(result))
            
            -- 处理特殊工具的结果
            if tool_name == "think_task" then
                self:handle_think_task_result(result)
            elseif tool_name == "finish_task" then
                self:handle_finish_task_result(result)
            else
                self:output("✅ 工具执行结果: " .. (result.message or "完成"))
            end
        else
            utils.log("error", "解析函数参数失败: " .. arguments)
            self:output("❌ 函数参数解析失败")
        end
    end
end

-- 处理think_task结果
function Agent:handle_think_task_result(result)
    if result.success then
        self.current_task_id = result.task_id
        self:output("📝 任务创建成功!")
        self:output("📋 任务描述: " .. result.task_description)
        self:output("✅ 包含 " .. #result.todos .. " 个待办事项")
        
        -- 列出todos
        for i, todo in ipairs(result.todos) do
            self:output("  " .. i .. ". " .. todo)
        end
        
        -- 开始工作循环
        self:start_work_loop()
    else
        self:output("❌ 任务创建失败: " .. (result.error or "未知错误"))
        self:stop()
    end
end

-- 处理finish_task结果
function Agent:handle_finish_task_result(result)
    if result.success then
        self:output("🎉 任务完成!")
        self:output("📄 总结: " .. result.summary)
        self:stop()
    else
        self:output("❌ 任务完成标记失败: " .. (result.error or "未知错误"))
        self:stop()
    end
end

-- 开始工作循环
function Agent:start_work_loop()
    self.status = M.AGENT_STATUS.WORKING
    self.loop_running = true
    self:output("🚀 开始执行任务...")
    
    -- 异步执行工作循环
    vim.schedule(function()
        self:work_loop()
    end)
end

-- 工作循环
function Agent:work_loop()
    if self.stop_requested or not self.loop_running then
        return
    end
    
    -- 检查任务是否完成
    if task.is_task_complete(self.current_task_id) then
        self:output("✅ 所有任务已完成")
        self:stop()
        return
    end
    
    -- 获取下一个待执行的todo
    local next_todo = task.get_next_todo(self.current_task_id)
    if not next_todo then
        self:output("ℹ️  没有更多待办事项，任务可能已完成")
        self:stop()
        return
    end
    
    -- 标记todo为进行中
    task.update_todo_status(self.current_task_id, next_todo.id, task.TODO_STATUS.IN_PROGRESS)
    
    self:output("📌 正在处理: " .. next_todo.description)
    
    -- 处理当前todo
    self:process_todo(next_todo)
end

-- 处理单个todo
function Agent:process_todo(todo)
    -- 准备消息
    local todo_message = "请完成以下任务: " .. todo.description
    context.add_user_message(self.current_context_id, todo_message)
    
    -- 获取可用工具
    local available_tools = tool.get_all_function_call_formats()
    
    -- 调用Provider
    local messages = context.get_formatted_messages(self.current_context_id)
    local options = {
        stream = true,
        tools = available_tools,
        max_tokens = 2048
    }
    
    local response_buffer = ""
    local function_call_buffer = {}
    
    provider.request(messages, options, function(content, meta)
        if meta and meta.error then
            self:output("❌ 错误: " .. (meta.error or "未知错误"))
            task.update_todo_status(self.current_task_id, todo.id, task.TODO_STATUS.FAILED, "API请求失败")
            self:continue_work_loop()
            return
        end
        
        if meta and meta.done then
            -- 处理完整的响应
            if #function_call_buffer > 0 then
                self:handle_function_calls(function_call_buffer)
            elseif response_buffer ~= "" then
                context.add_assistant_message(self.current_context_id, response_buffer)
            end
            
            -- 继续工作循环
            self:continue_work_loop()
            return
        end
        
        if meta and meta.type == "content" and content then
            response_buffer = response_buffer .. content
            self:output(content, { append = true })
        elseif meta and meta.type == "function_call" and content then
            table.insert(function_call_buffer, content)
        end
    end)
end

-- 继续工作循环
function Agent:continue_work_loop()
    if self.loop_running and not self.stop_requested then
        -- 延迟一下继续循环，避免过快的递归
        vim.defer_fn(function()
            self:work_loop()
        end, 100)
    end
end

-- 停止Agent
function Agent:stop()
    self.stop_requested = true
    self.loop_running = false
    self.status = M.AGENT_STATUS.STOPPED
    
    utils.log("info", "Agent已停止")
    self:output("🛑 Agent已停止")
end

-- 暂停Agent
function Agent:pause()
    if self.status == M.AGENT_STATUS.WORKING then
        self.status = M.AGENT_STATUS.PAUSED
        utils.log("info", "Agent已暂停")
        self:output("⏸️  Agent已暂停")
        return true
    end
    return false
end

-- 恢复Agent
function Agent:resume()
    if self.status == M.AGENT_STATUS.PAUSED then
        self.status = M.AGENT_STATUS.WORKING
        utils.log("info", "Agent已恢复")
        self:output("▶️  Agent已恢复")
        self:continue_work_loop()
        return true
    end
    return false
end

-- 输出消息
function Agent:output(message, options)
    options = options or {}
    
    if self.callbacks.on_output then
        self.callbacks.on_output(message, options)
    end
    
    -- 同时记录到日志
    utils.log("info", "Agent输出: " .. message)
end

-- 获取Agent状态
function Agent:get_status()
    return {
        id = self.id,
        status = self.status,
        current_task_id = self.current_task_id,
        current_context_id = self.current_context_id,
        loop_running = self.loop_running,
        stop_requested = self.stop_requested,
        created_at = self.created_at
    }
end

-- 获取任务进度
function Agent:get_progress()
    if not self.current_task_id then
        return 0
    end
    
    return task.get_task_progress(self.current_task_id)
end

-- 获取任务详情
function Agent:get_task_details()
    if not self.current_task_id then
        return nil
    end
    
    return task.get_task_details(self.current_task_id)
end

-- 取消当前任务
function Agent:cancel_task()
    if self.current_task_id then
        task.cancel_task(self.current_task_id)
        self:output("❌ 任务已取消")
        self:stop()
        return true
    end
    return false
end

-- 模块级别的函数

-- 初始化Agent模块
function M.init(config)
    M.config = config
    M.current_agent = nil
    utils.log("info", "Agent模块初始化完成")
end

-- 启动新的Agent
function M.start(query, callbacks)
    if M.current_agent and M.current_agent.status ~= M.AGENT_STATUS.STOPPED then
        utils.log("warn", "已有Agent在运行中")
        return false
    end
    
    M.current_agent = Agent.new(callbacks)
    return M.current_agent:start(query, callbacks)
end

-- 停止当前Agent
function M.stop()
    if M.current_agent then
        M.current_agent:stop()
        return true
    end
    return false
end

-- 暂停当前Agent
function M.pause()
    if M.current_agent then
        return M.current_agent:pause()
    end
    return false
end

-- 恢复当前Agent
function M.resume()
    if M.current_agent then
        return M.current_agent:resume()
    end
    return false
end

-- 获取当前Agent状态
function M.get_status()
    if M.current_agent then
        return M.current_agent:get_status()
    end
    return nil
end

-- 获取当前任务进度
function M.get_progress()
    if M.current_agent then
        return M.current_agent:get_progress()
    end
    return 0
end

-- 获取当前任务详情
function M.get_task_details()
    if M.current_agent then
        return M.current_agent:get_task_details()
    end
    return nil
end

-- 取消当前任务
function M.cancel_task()
    if M.current_agent then
        return M.current_agent:cancel_task()
    end
    return false
end

-- 检查Agent是否在运行
function M.is_running()
    return M.current_agent and M.current_agent.status ~= M.AGENT_STATUS.STOPPED
end

-- 获取Agent历史
function M.get_history()
    if M.current_agent and M.current_agent.current_context_id then
        return context.get_messages(M.current_agent.current_context_id)
    end
    return {}
end

-- 清理Agent资源
function M.cleanup()
    if M.current_agent then
        M.current_agent:stop()
        
        -- 清理上下文
        if M.current_agent.current_context_id then
            context.delete_context(M.current_agent.current_context_id)
        end
        
        M.current_agent = nil
    end
    
    utils.log("info", "Agent资源清理完成")
end

-- 重置Agent
function M.reset()
    M.cleanup()
    utils.log("info", "Agent重置完成")
end

-- 获取Agent统计信息
function M.get_stats()
    local stats = {
        current_agent = M.current_agent and M.current_agent:get_status() or nil,
        is_running = M.is_running(),
        total_tasks = task.count_tasks and task.count_tasks() or 0,
        active_tasks = #task.get_active_tasks(),
    }
    
    return stats
end

-- 导出Agent数据
function M.export_data()
    local export_data = {
        current_agent_status = M.get_status(),
        history = M.get_history(),
        task_details = M.get_task_details(),
        exported_at = utils.get_timestamp()
    }
    
    return export_data
end

return M 