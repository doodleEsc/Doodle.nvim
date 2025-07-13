-- lua/doodle/context.lua
local utils = require("doodle.utils")
local M = {}

-- 消息类型枚举
M.MESSAGE_TYPE = {
    SYSTEM = "system",
    USER = "user", 
    ASSISTANT = "assistant",
    TOOL = "tool",
    FUNCTION = "function"
}

-- 消息角色枚举
M.MESSAGE_ROLE = {
    SYSTEM = "system",
    USER = "user",
    ASSISTANT = "assistant",
    TOOL = "tool"
}

-- 上下文存储
M.contexts = {}

-- 初始化
function M.init(config)
    M.config = config
    M.contexts = {}
    utils.log("info", "消息上下文模块初始化完成")
end

-- 加载配置
function M.load(config)
    M.init(config)
end

-- 创建新的上下文
function M.create_context(context_id, system_message)
    local context = {
        id = context_id,
        messages = {},
        created_at = utils.get_timestamp(),
        updated_at = utils.get_timestamp(),
        metadata = {}
    }
    
    -- 添加系统消息
    if system_message then
        M.add_message(context_id, M.MESSAGE_TYPE.SYSTEM, system_message)
    end
    
    M.contexts[context_id] = context
    utils.log("info", "创建新上下文: " .. context_id)
    
    return context_id
end

-- 获取上下文
function M.get_context(context_id)
    return M.contexts[context_id]
end

-- 添加消息
function M.add_message(context_id, message_type, content, metadata)
    local context = M.contexts[context_id]
    if not context then
        utils.log("error", "上下文不存在: " .. context_id)
        return false
    end
    
    local message = {
        id = utils.generate_uuid(),
        type = message_type,
        role = M.get_role_from_type(message_type),
        content = content,
        timestamp = utils.get_timestamp(),
        metadata = metadata or {}
    }
    
    table.insert(context.messages, message)
    context.updated_at = utils.get_timestamp()
    
    utils.log("debug", "添加消息到上下文: " .. context_id .. " [" .. message_type .. "]")
    return message.id
end

-- 从消息类型获取角色
function M.get_role_from_type(message_type)
    local role_map = {
        [M.MESSAGE_TYPE.SYSTEM] = M.MESSAGE_ROLE.SYSTEM,
        [M.MESSAGE_TYPE.USER] = M.MESSAGE_ROLE.USER,
        [M.MESSAGE_TYPE.ASSISTANT] = M.MESSAGE_ROLE.ASSISTANT,
        [M.MESSAGE_TYPE.TOOL] = M.MESSAGE_ROLE.TOOL,
        [M.MESSAGE_TYPE.FUNCTION] = M.MESSAGE_ROLE.TOOL
    }
    
    return role_map[message_type] or M.MESSAGE_ROLE.USER
end

-- 添加用户消息
function M.add_user_message(context_id, content, metadata)
    return M.add_message(context_id, M.MESSAGE_TYPE.USER, content, metadata)
end

-- 添加助手消息
function M.add_assistant_message(context_id, content, metadata)
    return M.add_message(context_id, M.MESSAGE_TYPE.ASSISTANT, content, metadata)
end

-- 添加工具消息
function M.add_tool_message(context_id, tool_name, tool_call_id, content, metadata)
    local tool_metadata = metadata or {}
    tool_metadata.tool_name = tool_name
    tool_metadata.tool_call_id = tool_call_id
    
    return M.add_message(context_id, M.MESSAGE_TYPE.TOOL, content, tool_metadata)
end

-- 添加函数调用消息
function M.add_function_call_message(context_id, function_name, arguments, call_id, metadata)
    local func_metadata = metadata or {}
    func_metadata.function_name = function_name
    func_metadata.arguments = arguments
    func_metadata.call_id = call_id
    
    local content = {
        function_call = {
            name = function_name,
            arguments = arguments
        }
    }
    
    return M.add_message(context_id, M.MESSAGE_TYPE.FUNCTION, content, func_metadata)
end

-- 获取消息列表
function M.get_messages(context_id, limit)
    local context = M.contexts[context_id]
    if not context then
        return {}
    end
    
    local messages = context.messages
    if limit and limit > 0 then
        local start_index = math.max(1, #messages - limit + 1)
        local limited_messages = {}
        for i = start_index, #messages do
            table.insert(limited_messages, messages[i])
        end
        return limited_messages
    end
    
    return messages
end

-- 获取格式化的消息列表(用于API调用)
function M.get_formatted_messages(context_id, limit)
    local messages = M.get_messages(context_id, limit)
    local formatted_messages = {}
    
    for _, message in ipairs(messages) do
        local formatted = {
            role = message.role,
            content = message.content
        }
        
        -- 处理工具调用相关的消息格式
        if message.type == M.MESSAGE_TYPE.TOOL then
            formatted.tool_call_id = message.metadata.tool_call_id
            formatted.name = message.metadata.tool_name
        elseif message.type == M.MESSAGE_TYPE.FUNCTION then
            formatted.function_call = message.content.function_call
        end
        
        table.insert(formatted_messages, formatted)
    end
    
    return formatted_messages
end

-- 获取最后一条消息
function M.get_last_message(context_id)
    local context = M.contexts[context_id]
    if not context or #context.messages == 0 then
        return nil
    end
    
    return context.messages[#context.messages]
end

-- 获取特定类型的消息
function M.get_messages_by_type(context_id, message_type)
    local context = M.contexts[context_id]
    if not context then
        return {}
    end
    
    local filtered_messages = {}
    for _, message in ipairs(context.messages) do
        if message.type == message_type then
            table.insert(filtered_messages, message)
        end
    end
    
    return filtered_messages
end

-- 更新消息
function M.update_message(context_id, message_id, content, metadata)
    local context = M.contexts[context_id]
    if not context then
        utils.log("error", "上下文不存在: " .. context_id)
        return false
    end
    
    for _, message in ipairs(context.messages) do
        if message.id == message_id then
            message.content = content
            message.metadata = utils.deep_copy(metadata or message.metadata)
            message.timestamp = utils.get_timestamp()
            context.updated_at = utils.get_timestamp()
            
            utils.log("debug", "更新消息: " .. message_id)
            return true
        end
    end
    
    utils.log("error", "消息不存在: " .. message_id)
    return false
end

-- 删除消息
function M.delete_message(context_id, message_id)
    local context = M.contexts[context_id]
    if not context then
        utils.log("error", "上下文不存在: " .. context_id)
        return false
    end
    
    for i, message in ipairs(context.messages) do
        if message.id == message_id then
            table.remove(context.messages, i)
            context.updated_at = utils.get_timestamp()
            utils.log("debug", "删除消息: " .. message_id)
            return true
        end
    end
    
    utils.log("error", "消息不存在: " .. message_id)
    return false
end

-- 清空上下文
function M.clear_context(context_id)
    local context = M.contexts[context_id]
    if not context then
        utils.log("error", "上下文不存在: " .. context_id)
        return false
    end
    
    context.messages = {}
    context.updated_at = utils.get_timestamp()
    
    utils.log("info", "清空上下文: " .. context_id)
    return true
end

-- 删除上下文
function M.delete_context(context_id)
    if not M.contexts[context_id] then
        utils.log("error", "上下文不存在: " .. context_id)
        return false
    end
    
    M.contexts[context_id] = nil
    utils.log("info", "删除上下文: " .. context_id)
    return true
end

-- 获取上下文统计信息
function M.get_context_stats(context_id)
    local context = M.contexts[context_id]
    if not context then
        return nil
    end
    
    local stats = {
        total_messages = #context.messages,
        message_types = {},
        created_at = context.created_at,
        updated_at = context.updated_at
    }
    
    -- 统计各类型消息数量
    for _, message in ipairs(context.messages) do
        stats.message_types[message.type] = (stats.message_types[message.type] or 0) + 1
    end
    
    return stats
end

-- 获取所有上下文
function M.get_all_contexts()
    return M.contexts
end

-- 克隆上下文
function M.clone_context(source_context_id, target_context_id)
    local source_context = M.contexts[source_context_id]
    if not source_context then
        utils.log("error", "源上下文不存在: " .. source_context_id)
        return false
    end
    
    local target_context = {
        id = target_context_id,
        messages = utils.deep_copy(source_context.messages),
        created_at = utils.get_timestamp(),
        updated_at = utils.get_timestamp(),
        metadata = utils.deep_copy(source_context.metadata)
    }
    
    M.contexts[target_context_id] = target_context
    utils.log("info", "克隆上下文: " .. source_context_id .. " -> " .. target_context_id)
    
    return target_context_id
end

-- 合并上下文
function M.merge_contexts(target_context_id, source_context_id)
    local target_context = M.contexts[target_context_id]
    local source_context = M.contexts[source_context_id]
    
    if not target_context then
        utils.log("error", "目标上下文不存在: " .. target_context_id)
        return false
    end
    
    if not source_context then
        utils.log("error", "源上下文不存在: " .. source_context_id)
        return false
    end
    
    -- 合并消息
    for _, message in ipairs(source_context.messages) do
        table.insert(target_context.messages, utils.deep_copy(message))
    end
    
    target_context.updated_at = utils.get_timestamp()
    
    utils.log("info", "合并上下文: " .. source_context_id .. " -> " .. target_context_id)
    return true
end

-- 截断上下文(保留最新的n条消息)
function M.truncate_context(context_id, max_messages)
    local context = M.contexts[context_id]
    if not context then
        utils.log("error", "上下文不存在: " .. context_id)
        return false
    end
    
    if #context.messages <= max_messages then
        return true
    end
    
    local start_index = #context.messages - max_messages + 1
    local truncated_messages = {}
    
    for i = start_index, #context.messages do
        table.insert(truncated_messages, context.messages[i])
    end
    
    context.messages = truncated_messages
    context.updated_at = utils.get_timestamp()
    
    utils.log("info", "截断上下文: " .. context_id .. " (保留 " .. max_messages .. " 条消息)")
    return true
end

-- 导出上下文数据
function M.export_context_data()
    local export_data = {
        contexts = M.contexts,
        exported_at = utils.get_timestamp()
    }
    
    return export_data
end

-- 导入上下文数据
function M.import_context_data(data)
    if not data or type(data) ~= "table" then
        return false, "无效的导入数据"
    end
    
    if data.contexts then
        M.contexts = data.contexts
    end
    
    utils.log("info", "导入上下文数据完成")
    return true
end

-- 验证消息结构
function M.validate_message(message)
    if type(message) ~= "table" then
        return false, "消息必须是表类型"
    end
    
    if not message.type or not M.MESSAGE_TYPE[message.type:upper()] then
        return false, "消息类型无效"
    end
    
    if utils.is_string_empty(message.content) then
        return false, "消息内容不能为空"
    end
    
    return true
end

-- 搜索消息
function M.search_messages(context_id, query, message_type)
    local context = M.contexts[context_id]
    if not context then
        return {}
    end
    
    local results = {}
    query = query:lower()
    
    for _, message in ipairs(context.messages) do
        local match_type = not message_type or message.type == message_type
        local match_content = false
        
        if type(message.content) == "string" then
            match_content = message.content:lower():find(query, 1, true) ~= nil
        elseif type(message.content) == "table" then
            local content_str = vim.inspect(message.content):lower()
            match_content = content_str:find(query, 1, true) ~= nil
        end
        
        if match_type and match_content then
            table.insert(results, message)
        end
    end
    
    return results
end

return M 