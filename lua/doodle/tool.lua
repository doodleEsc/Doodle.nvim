-- lua/doodle/tool.lua
local utils = require("doodle.utils")
local tools_module = require("doodle.tools")
local M = {}

-- 工具注册表
M.tools = {}

-- 内置工具引用
M.builtin_tools = {}

-- 初始化
function M.init(config)
    M.config = config
    M.tools = {}
    utils.log("info", "工具模块初始化完成")
end

-- 加载工具
function M.load(config)
    M.config = config
    
    -- 加载内置工具
    M.load_builtin_tools()
    
    -- 加载自定义工具
    M.load_custom_tools(config.custom_tools or {})
    
    -- 将工具存储到配置中
    config.tools = M.tools
    
    utils.log("info", "工具模块加载完成，共加载 " .. M.count_tools() .. " 个工具")
end

-- 加载内置工具
function M.load_builtin_tools()
    -- 从工具模块加载所有内置工具
    M.builtin_tools = tools_module.load_builtin_tools()
    
    -- 注册内置工具到工具注册表
    for name, tool in pairs(M.builtin_tools) do
        M.tools[name] = tool
        utils.log("debug", "注册内置工具: " .. name)
    end
    
    utils.log("info", "内置工具加载完成")
end

-- 加载自定义工具
function M.load_custom_tools(custom_tools)
    if not custom_tools or type(custom_tools) ~= "table" then
        return
    end
    
    for _, tool in ipairs(custom_tools) do
        local valid, error_msg = utils.validate_tool(tool)
        if valid then
            M.register_tool(tool)
            utils.log("info", "加载自定义工具: " .. tool.name)
        else
            utils.log("warn", "无效的自定义工具: " .. error_msg)
        end
    end
end

-- 注册工具
function M.register_tool(tool)
    if not tool or not tool.name then
        utils.log("error", "工具注册失败：无效的工具对象")
        return false
    end
    
    local valid, error_msg = utils.validate_tool(tool)
    if not valid then
        utils.log("error", "工具注册失败：" .. error_msg)
        return false
    end
    
    -- 设置默认参数结构
    if not tool.parameters then
        tool.parameters = {
            type = "object",
            properties = {},
            required = {}
        }
    end
    
    M.tools[tool.name] = tool
    utils.log("debug", "注册工具: " .. tool.name)
    return true
end

-- 注销工具
function M.unregister_tool(tool_name)
    if tools_module.is_builtin_tool(tool_name) then
        utils.log("warn", "不能注销内置工具: " .. tool_name)
        return false
    end
    
    M.tools[tool_name] = nil
    utils.log("info", "注销工具: " .. tool_name)
    return true
end

-- 获取工具
function M.get_tool(tool_name)
    return M.tools[tool_name]
end

-- 获取所有工具
function M.get_all_tools()
    return M.tools
end

-- 列出工具信息
function M.list_tools()
    local tool_list = {}
    for name, tool in pairs(M.tools) do
        table.insert(tool_list, {
            name = name,
            description = tool.description,
            parameters = tool.parameters
        })
    end
    return tool_list
end

-- 执行工具
function M.execute_tool(tool_name, args)
    local tool = M.tools[tool_name]
    if not tool then
        utils.log("error", "工具不存在: " .. tool_name)
        return {
            success = false,
            error = "工具不存在: " .. tool_name
        }
    end
    
    utils.log("info", "执行工具: " .. tool_name)
    
    -- 检查是否是新的工具对象（有safe_execute方法）
    if tool.safe_execute and type(tool.safe_execute) == "function" then
        -- 新的工具对象，使用safe_execute方法
        return tool:safe_execute(args)
    else
        -- 兼容旧的工具格式
        -- 验证参数
        local valid, error_msg = M.validate_tool_args(tool, args)
        if not valid then
            utils.log("error", "工具参数验证失败: " .. error_msg)
            return {
                success = false,
                error = "参数验证失败: " .. error_msg
            }
        end
        
        -- 执行工具
        local success, result = utils.safe_call(tool.execute, args)
        if not success then
            utils.log("error", "工具执行失败: " .. tostring(result))
            return {
                success = false,
                error = "工具执行失败: " .. tostring(result)
            }
        end
        
        return result
    end
end

-- 验证工具参数
function M.validate_tool_args(tool, args)
    if not tool.parameters then
        return true -- 如果没有参数要求，则通过验证
    end
    
    local params = tool.parameters
    args = args or {}
    
    -- 检查必需参数
    if params.required then
        for _, required_param in ipairs(params.required) do
            if not args[required_param] then
                return false, "缺少必需参数: " .. required_param
            end
        end
    end
    
    -- 检查参数类型
    if params.properties then
        for param_name, param_spec in pairs(params.properties) do
            local value = args[param_name]
            if value ~= nil then
                local valid, error_msg = M.validate_param_type(value, param_spec)
                if not valid then
                    return false, "参数 " .. param_name .. " " .. error_msg
                end
            end
        end
    end
    
    return true
end

-- 验证参数类型
function M.validate_param_type(value, param_spec)
    local value_type = type(value)
    local expected_type = param_spec.type
    
    if expected_type == "string" and value_type ~= "string" then
        return false, "类型错误，期望 string，实际 " .. value_type
    elseif expected_type == "number" and value_type ~= "number" then
        return false, "类型错误，期望 number，实际 " .. value_type
    elseif expected_type == "boolean" and value_type ~= "boolean" then
        return false, "类型错误，期望 boolean，实际 " .. value_type
    elseif expected_type == "array" and value_type ~= "table" then
        return false, "类型错误，期望 array，实际 " .. value_type
    elseif expected_type == "object" and value_type ~= "table" then
        return false, "类型错误，期望 object，实际 " .. value_type
    end
    
    -- 检查枚举值
    if param_spec.enum then
        local valid = false
        for _, enum_value in ipairs(param_spec.enum) do
            if value == enum_value then
                valid = true
                break
            end
        end
        if not valid then
            return false, "值不在允许的枚举范围内"
        end
    end
    
    return true
end

-- 获取工具的函数调用格式 (OpenAI tools格式)
function M.get_function_call_format(tool_name)
    local tool = M.tools[tool_name]
    if not tool then
        return nil
    end
    
    -- 检查是否是新的工具对象（有to_openai_format方法）
    if tool.to_openai_format and type(tool.to_openai_format) == "function" then
        return tool:to_openai_format()
    else
        -- 兼容旧的工具格式
        return {
            type = "function",
            ["function"] = {
                name = tool.name,
                description = tool.description,
                parameters = tool.parameters
            }
        }
    end
end

-- 获取所有工具的函数调用格式
function M.get_all_function_call_formats()
    local formats = {}
    for name, tool in pairs(M.tools) do
        table.insert(formats, M.get_function_call_format(name))
    end
    return formats
end

-- 检查工具是否存在
function M.has_tool(tool_name)
    return M.tools[tool_name] ~= nil
end

-- 统计工具数量
function M.count_tools()
    local count = 0
    for _ in pairs(M.tools) do
        count = count + 1
    end
    return count
end

-- 获取工具分类
function M.get_tool_categories()
    local categories = {
        builtin = {},
        custom = {}
    }
    
    for name, tool in pairs(M.tools) do
        if tools_module.is_builtin_tool(name) then
            table.insert(categories.builtin, name)
        else
            table.insert(categories.custom, name)
        end
    end
    
    return categories
end

-- 搜索工具
function M.search_tools(query)
    local results = {}
    query = query:lower()
    
    for name, tool in pairs(M.tools) do
        local match_name = name:lower():find(query, 1, true) ~= nil
        local match_desc = tool.description:lower():find(query, 1, true) ~= nil
        
        if match_name or match_desc then
            table.insert(results, {
                name = name,
                description = tool.description,
                score = match_name and 2 or 1 -- 名称匹配权重更高
            })
        end
    end
    
    -- 按分数排序
    table.sort(results, function(a, b) return a.score > b.score end)
    
    return results
end

-- 复制工具
function M.clone_tool(source_tool_name, target_tool_name)
    local source_tool = M.tools[source_tool_name]
    if not source_tool then
        utils.log("error", "源工具不存在: " .. source_tool_name)
        return false
    end
    
    local cloned_tool = utils.deep_copy(source_tool)
    cloned_tool.name = target_tool_name
    
    return M.register_tool(cloned_tool)
end

-- 导出工具数据
function M.export_tool_data()
    local export_data = {
        tools = {},
        exported_at = utils.get_timestamp()
    }
    
    -- 只导出自定义工具
    for name, tool in pairs(M.tools) do
        if not tools_module.is_builtin_tool(name) then
            export_data.tools[name] = tool
        end
    end
    
    return export_data
end

-- 导入工具数据
function M.import_tool_data(data)
    if not data or type(data) ~= "table" or not data.tools then
        return false, "无效的导入数据"
    end
    
    local imported_count = 0
    for name, tool in pairs(data.tools) do
        if M.register_tool(tool) then
            imported_count = imported_count + 1
        end
    end
    
    utils.log("info", "导入工具数据完成，共导入 " .. imported_count .. " 个工具")
    return true
end

-- 重置工具
function M.reset_tools()
    M.tools = {}
    M.load_builtin_tools()
    utils.log("info", "工具重置完成")
end

-- 获取工具使用统计
function M.get_tool_usage_stats()
    local stats = {}
    
    for name, tool in pairs(M.tools) do
        stats[name] = {
            name = name,
            description = tool.description,
            is_builtin = tools_module.is_builtin_tool(name),
            -- 这里可以添加更多统计信息，比如调用次数等
        }
    end
    
    return stats
end

-- 获取内置工具模块
function M.get_builtin_tools_module()
    return tools_module
end

-- 重新加载内置工具（用于开发调试）
function M.reload_builtin_tools()
    -- 重新加载工具模块
    package.loaded["doodle.tools"] = nil
    tools_module = require("doodle.tools")
    
    -- 清除内置工具
    for name in pairs(M.builtin_tools) do
        M.tools[name] = nil
    end
    M.builtin_tools = {}
    
    -- 重新加载内置工具
    M.load_builtin_tools()
    
    utils.log("info", "内置工具重新加载完成")
end

-- 验证所有内置工具
function M.validate_all_builtin_tools()
    return tools_module.validate_all_builtin_tools()
end

return M 