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
    
    utils.log("dev", "新 Agent 已创建, ID: " .. self.id)
    return self
end

-- 启动Agent
function Agent:start(query)
    if self.status ~= M.AGENT_STATUS.IDLE then
        utils.log("warn", "Agent 已经在运行中，无法启动新任务")
        return false
    end
    
    utils.log("dev", "Agent:start 调用, 查询: " .. query)

    self:trigger_callback("on_start")
    
    self.status = M.AGENT_STATUS.THINKING
    self.stop_requested = false
    
    utils.log("dev", "Agent 状态设置为 THINKING, 准备思考任务")
    -- 创建新上下文
    self.current_context_id = context.create_context()
    context.add_message(self.current_context_id, "user", query)
    
    -- 启动思考任务阶段
    self:think_task(query)
    
    return true
end

-- 思考任务阶段
function Agent:think_task(query)
    self.status = M.AGENT_STATUS.THINKING
    self.stop_requested = false
    
    utils.log("dev", "Agent 状态设置为 THINKING, 准备启动主循环")
    -- 创建新任务和上下文
    self.current_task_id = task.create_task(query)
    
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
                -- 直接文本回复完成，停止Agent
                self:stop()
            else
                -- 没有内容，也要停止Agent
                self:stop()
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

		print("agent:process_todo.request.callback" .. content)
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
    if self.status == M.AGENT_STATUS.STOPPED then
        utils.log("dev", "Agent.stop 调用但状态已经是STOPPED，跳过")
        return
    end
    utils.log("dev", "Agent.stop 调用, 原状态: " .. self.status)
    self.stop_requested = true
    self.status = M.AGENT_STATUS.STOPPED
    utils.log("dev", "Agent状态已设置为: " .. self.status)
    self:trigger_callback("on_stop")
    utils.log("dev", "Agent.stop 完成，已触发on_stop回调")
end

-- 暂停Agent
function Agent:pause()
    if self.status == M.AGENT_STATUS.WORKING then
        utils.log("dev", "Agent.pause 调用, 状态设置为 PAUSED")
        self.status = M.AGENT_STATUS.PAUSED
        self:trigger_callback("on_pause")
        return true
    end
    return false
end

-- 恢复Agent
function Agent:resume()
    if self.status == M.AGENT_STATUS.PAUSED then
        utils.log("dev", "Agent.resume 调用, 状态恢复为 WORKING")
        self.status = M.AGENT_STATUS.WORKING
        self:trigger_callback("on_resume")
        return true
    end
    return false
end

-- 触发回调
function Agent:trigger_callback(event, ...)
    if self.callbacks and self.callbacks[event] then
        utils.log("dev", "触发回调: " .. event, { ... })
        pcall(self.callbacks[event], ...)
    end
end



-- 输出消息
function Agent:output(message, options)
	print("agent:output" .. message)
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

    local is_active = M.current_agent and 
                      (M.current_agent.status == M.AGENT_STATUS.THINKING or M.current_agent.status == M.AGENT_STATUS.WORKING)

    -- 添加调试日志
    if M.current_agent then
        utils.log("dev", "检查Agent状态: " .. M.current_agent.status)
        utils.log("dev", "THINKING状态: " .. M.AGENT_STATUS.THINKING)
        utils.log("dev", "WORKING状态: " .. M.AGENT_STATUS.WORKING)
        utils.log("dev", "STOPPED状态: " .. M.AGENT_STATUS.STOPPED)
        utils.log("dev", "is_active结果: " .. tostring(is_active))
    else
        utils.log("dev", "当前没有Agent实例")
    end

    if is_active then
        utils.log("warn", "已有Agent在运行中，请等待其完成后再启动新任务。")
        -- 可以在这里触发一个UI错误提示
        local ui = require("doodle.ui")
        ui.output_error("正在处理中，请等待完成后再发送新消息")
        return false
    end
    
    M.current_agent = Agent.new(callbacks)
    return M.current_agent:start(query)
end

-- 发送消息给Agent
function M.send_message(message, callbacks)
    -- 获取UI实例用于回调
    local ui = require("doodle.ui")
    
    -- 设置默认回调
    local default_callbacks = {
        on_start = function()
            ui.on_generate_start()
            utils.log("info", "开始处理消息: " .. message:sub(1, 50) .. "...")
            utils.log("dev", "Agent on_start 回调触发")
        end,
        
        on_progress = function(progress)
            if progress.type == "tool_use" then
                ui.on_tool_calling(progress.tool_name)
                utils.log("dev", "Agent on_progress 回调触发: tool_use - " .. progress.tool_name)
            end
        end,
        
        on_chunk = function(chunk)
            if chunk and chunk.content then
                ui.append(chunk.content, { highlight = ui.highlights.ASSISTANT_MESSAGE })
                utils.log("dev", "Agent on_chunk 回调触发, 内容: " .. chunk.content)
            end
        end,
        
        on_output = function(message, options)
            if options and options.append then
                ui.append(message, { highlight = ui.highlights.ASSISTANT_MESSAGE })
                utils.log("dev", "Agent on_output 回调触发 (streaming), 内容: " .. message)
            else
                ui.output(message, { highlight = ui.highlights.ASSISTANT_MESSAGE })
                utils.log("dev", "Agent on_output 回调触发 (完整消息), 内容: " .. message)
            end
        end,
        
        on_complete = function(result)
            ui.on_generate_complete()
            utils.log("info", "消息处理完成")
            utils.log("dev", "Agent on_complete 回调触发")
        end,
        
        on_error = function(error_msg)
            ui.on_generate_error(error_msg)
            utils.log("error", "消息处理失败: " .. (error_msg or "未知错误"))
            utils.log("dev", "Agent on_error 回调触发")
        end,
        
        on_stop = function()
            ui.on_generate_complete()
            utils.log("info", "Agent已停止")
            utils.log("dev", "Agent on_stop 回调触发")
        end
    }
    
    -- 合并用户提供的回调
    if callbacks then
        for key, callback in pairs(callbacks) do
            default_callbacks[key] = callback
        end
    end
    
    -- 启动新的处理任务
    return M.start(message, default_callbacks)
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