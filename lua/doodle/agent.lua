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
    WORKING = "working", 
    STOPPED = "stopped"
}

-- 当前活跃的Agent实例
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
    self.context_id = nil
    self.current_task = nil  -- 由工具设置/清除
    self.current_job = nil   -- 当前正在执行的job（provider或tool）
    self.stop_requested = false
    self.created_at = utils.get_timestamp()
    
    utils.log("dev", "新 Agent 已创建, ID: " .. self.id)
    return self
end

-- 启动Agent
function Agent:start(query)
    if self.status ~= M.AGENT_STATUS.IDLE then
        utils.log("warn", "Agent 已经在运行中，无法启动新任务")
        return false, "Agent正在工作中"
    end
    
    utils.log("dev", "Agent:start 调用, 查询: " .. query)
    
    -- 设置为当前活跃agent
    M.current_agent = self
    
    -- 初始化工作状态
    self.status = M.AGENT_STATUS.WORKING
    self.stop_requested = false
    self.context_id = context.create_context()
    self.current_task = nil
    
    -- 添加用户消息到上下文
    context.add_message(self.context_id, "user", query)
    
    self:trigger_callback("on_start")
    
    -- 启动执行循环
    self:execute_loop()
    
    return true
end

-- 主执行循环
function Agent:execute_loop()
    if self.stop_requested then
        self:stop()
        return
    end
    
    utils.log("dev", "Agent 执行循环开始")
    
    -- 构造消息
    local messages = context.get_formatted_messages(self.context_id)
    
    -- 如果有当前任务，添加任务上下文
    if self.current_task then
        self:add_task_context_to_messages()
    end
    
    -- 构造选项
    local options = {
        stream = true,
        tools = tool.get_all_function_call_formats(),
        max_tokens = 2048
    }
    
    -- 调用provider，使用聚合的工具调用处理
    local response_buffer = ""
    local function_call_buffer = {}
    
    self.current_job = provider.request(messages, options, function(content, meta)
        self:handle_provider_response(content, meta, response_buffer, function_call_buffer)
    end)
end

-- 处理Provider响应
function Agent:handle_provider_response(content, meta, response_buffer, function_call_buffer)
    if self.stop_requested then
        return
    end
    
    if meta and meta.error then
        utils.log("error", "Provider错误: " .. (meta.error or "未知错误"))
        self:trigger_callback("on_error", meta.error)
        self:stop()
        return
    end
    
    if meta and meta.done then
        utils.log("dev", "Provider响应完成，处理聚合结果")
        
        -- 处理聚合的工具调用
        if #function_call_buffer > 0 then
            self:handle_function_calls(function_call_buffer)
        elseif response_buffer ~= "" then
            -- 纯文本响应，添加到上下文
            context.add_assistant_message(self.context_id, response_buffer)
            self:trigger_callback("on_content", response_buffer, { final = true })
        end
        
        -- 检查是否继续循环
        self:check_and_continue_loop()
        return
    end
    
    if meta and meta.type == "content" and content then
        response_buffer = response_buffer .. content
        self:trigger_callback("on_content", content, { append = true })
    elseif meta and meta.type == "function_call" and content then
        table.insert(function_call_buffer, content)
        utils.log("dev", "聚合工具调用: " .. (content.name or "unknown"))
    end
end

-- 添加任务上下文到消息
function Agent:add_task_context_to_messages()
    if not self.current_task then
        return
    end
    
    -- 获取未完成的todos
    local pending_todos = task.get_pending_todos(self.current_task.id)
    
    if #pending_todos > 0 then
        local task_prompt = "当前任务: " .. self.current_task.description .. "\n"
        task_prompt = task_prompt .. "待完成事项:\n"
        
        for i, todo in ipairs(pending_todos) do
            task_prompt = task_prompt .. i .. ". " .. todo.description .. " (状态: " .. todo.status .. ")\n"
        end
        
        task_prompt = task_prompt .. "\n请继续执行下一个待办事项。"
        
        context.add_message(self.context_id, "user", task_prompt)
        utils.log("dev", "添加任务上下文到消息")
    end
end

-- 处理聚合的工具调用 - 改为顺序执行
function Agent:handle_function_calls(function_calls)
    if #function_calls == 0 then
        -- 没有工具调用，直接检查继续
        self:check_and_continue_loop()
        return
    end
    
    utils.log("dev", "开始顺序执行 " .. #function_calls .. " 个工具调用")
    
    -- 顺序执行工具调用
    self:execute_tools_sequentially(function_calls, 1)
end

-- 顺序执行工具调用
function Agent:execute_tools_sequentially(function_calls, current_index)
    if self.stop_requested then
        utils.log("dev", "Agent已停止，中断工具执行")
        return
    end
    
    -- 检查是否所有工具都已执行完成
    if current_index > #function_calls then
        utils.log("dev", "所有 " .. #function_calls .. " 个工具顺序执行完成")
        -- 清空当前job
        self.current_job = nil
        -- 检查是否继续循环
        self:check_and_continue_loop()
        return
    end
    
    local func_call = function_calls[current_index]
    local tool_name = func_call.name
    
    utils.log("dev", "顺序执行工具 " .. current_index .. "/" .. #function_calls .. ": " .. tool_name)
    
    -- 执行当前工具，完成后自动执行下一个
    self:execute_tool_async(func_call, function()
        -- 当前工具完成后，异步调度下一个工具执行
        vim.schedule(function()
            self:execute_tools_sequentially(function_calls, current_index + 1)
        end)
    end)
end

-- 异步执行单个工具
function Agent:execute_tool_async(tool_call, completion_callback)
    local tool_name = tool_call.name
    local arguments = tool_call.arguments
    
    utils.log("dev", "准备执行工具: " .. tool_name)
    
    -- 解析参数
    local success, parsed_args = pcall(vim.json.decode, arguments)
    if not success then
        utils.log("error", "工具参数解析失败: " .. arguments)
        self:trigger_callback("on_error", "工具参数解析失败: " .. tool_name)
        -- 即使失败也要继续下一个工具
        completion_callback()
        return nil
    end
    
    self:trigger_callback("on_tool_start", tool_name, parsed_args)
    
    -- 异步执行工具
    local job = tool.execute_tool(tool_name, parsed_args, function(result, error)
        if self.stop_requested then
            utils.log("dev", "Agent已停止，忽略工具回调: " .. tool_name)
            return
        end
        
        if error then
            utils.log("error", "工具执行错误: " .. tool_name .. ", " .. error)
            self:trigger_callback("on_error", "工具执行错误: " .. error)
            -- 即使出错也要继续下一个工具
        else
            -- 添加工具消息到上下文
            context.add_tool_message(
                self.context_id,
                tool_name,
                tool_call.id or utils.generate_uuid(),
                vim.json.encode(result)
            )
            
            self:trigger_callback("on_tool_complete", tool_name, result)
            utils.log("dev", "工具执行成功: " .. tool_name)
        end
        
        -- 清空当前job引用
        self.current_job = nil
        
        -- 通知当前工具完成，可以执行下一个
        completion_callback()
    end)
    
    if job then
        -- 设置当前job为工具job
        self.current_job = job
        -- 启动工具执行
        job:start()
        utils.log("dev", "工具job已启动: " .. tool_name)
    else
        -- 如果job创建失败，也要继续下一个工具
        utils.log("error", "工具job创建失败: " .. tool_name)
        completion_callback()
    end
    
    return job
end

-- 检查是否继续循环 - 纯粹的状态检查
function Agent:check_and_continue_loop()
    utils.log("dev", "检查是否继续执行循环")
    
    -- 简单的状态检查：是否有任务且有待完成的todos
    if self.current_task then
        local has_pending = task.has_pending_todos(self.current_task.id)
        utils.log("dev", "当前任务: " .. self.current_task.id .. ", 有待办事项: " .. tostring(has_pending))
        
        if has_pending then
            -- 继续循环
            utils.log("dev", "有待办事项，继续执行循环")
            vim.schedule(function()
                self:execute_loop()
            end)
            return
        end
    end
    
    -- 没有任务或没有待办事项，停止
    utils.log("dev", "没有待办事项，停止Agent")
    self:stop()
end

-- 停止Agent
function Agent:stop()
    if self.status == M.AGENT_STATUS.STOPPED then
        return
    end
    
    utils.log("dev", "Agent停止，清理所有jobs")
    
    self.status = M.AGENT_STATUS.STOPPED
    self.stop_requested = true
    
    -- 停止当前job（provider或tool）
    if self.current_job and self.current_job.shutdown then
        utils.log("dev", "停止当前job")
        self.current_job:shutdown()
    end
    
    -- 清除当前活跃agent
    if M.current_agent == self then
        M.current_agent = nil
    end
    
    self:trigger_callback("on_stop")
end

-- 重置Agent（实现复用）
function Agent:reset()
    utils.log("dev", "Agent重置")
    
    -- 清理当前状态
    if self.current_job and self.current_job.shutdown then
        self.current_job:shutdown()
    end
    
    if self.context_id then
        context.delete_context(self.context_id)
    end
    
    -- 重置为初始状态
    self.status = M.AGENT_STATUS.IDLE
    self.context_id = nil
    self.current_task = nil
    self.current_job = nil
    self.stop_requested = false
    
    -- 清除当前活跃agent引用
    if M.current_agent == self then
        M.current_agent = nil
    end
    
    self:trigger_callback("on_reset")
end

-- 触发回调
function Agent:trigger_callback(event, ...)
    if self.callbacks and self.callbacks[event] then
        utils.log("dev", "触发回调: " .. event)
        pcall(self.callbacks[event], ...)
    end
end



-- 获取Agent状态
function Agent:get_status()
    return {
        id = self.id,
        status = self.status,
        current_task_id = self.current_task and self.current_task.id or nil,
        context_id = self.context_id,
        created_at = self.created_at
    }
end

-- 获取任务进度
function Agent:get_progress()
    if not self.current_task then
        return 0
    end
    
    return task.get_task_progress(self.current_task.id)
end

-- 获取任务详情
function Agent:get_task_details()
    return self.current_task
end

-- 取消当前任务
function Agent:cancel_task()
    if self.current_task then
        task.cancel_task(self.current_task.id)
        self.current_task = nil
        self:stop()
        return true
    end
    return false
end

-- 模块级别方法

-- 创建新Agent
function M.create_agent(callbacks)
    return Agent.new(callbacks)
end

-- 获取当前活跃的Agent（供工具使用）
function M.get_current_agent()
    return M.current_agent
end

-- 启动Agent（便捷方法）
function M.start(query, callbacks)
    -- 如果有活跃agent且不是IDLE状态，返回错误
    if M.current_agent and M.current_agent.status ~= M.AGENT_STATUS.IDLE then
        utils.log("warn", "已有Agent在运行中")
        return false, "已有Agent在运行中"
    end
    
    -- 创建新agent或重用现有agent
    local agent = M.current_agent
    if not agent or agent.status ~= M.AGENT_STATUS.IDLE then
        agent = M.create_agent(callbacks)
    end
    
    return agent:start(query)
end



-- 停止当前Agent
function M.stop()
    if M.current_agent then
        M.current_agent:stop()
        return true
    end
    return false
end

-- 重置当前Agent
function M.reset()
    if M.current_agent then
        M.current_agent:reset()
        return true
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
    return M.current_agent and M.current_agent.status == M.AGENT_STATUS.WORKING
end

-- 获取Agent历史
function M.get_history()
    if M.current_agent and M.current_agent.context_id then
        return context.get_messages(M.current_agent.context_id)
    end
    return {}
end

return M 