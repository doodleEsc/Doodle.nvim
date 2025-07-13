-- lua/doodle/tool.lua
local utils = require("doodle.utils")
local task = require("doodle.task")
local prompt = require("doodle.prompt")
local M = {}

-- 工具注册表
M.tools = {}

-- 内置工具
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
    -- think_task 工具
    M.builtin_tools.think_task = {
        name = "think_task",
        description = "分析用户请求并将其分解为具体的任务和todo项",
        parameters = {
            type = "object",
            properties = {
                user_query = {
                    type = "string",
                    description = "用户的原始请求"
                },
                analysis = {
                    type = "string", 
                    description = "对用户请求的分析和理解"
                },
                task_description = {
                    type = "string",
                    description = "任务的总体描述"
                },
                todos = {
                    type = "array",
                    items = {
                        type = "string"
                    },
                    description = "具体的todo项目列表"
                }
            },
            required = {"user_query", "analysis", "task_description", "todos"}
        },
        execute = function(args)
            utils.log("info", "执行 think_task 工具")
            
            -- 验证参数
            if not args.user_query or not args.task_description or not args.todos then
                return {
                    success = false,
                    error = "缺少必要参数"
                }
            end
            
            -- 创建任务
            local task_id = task.create_task(args.user_query, args.task_description, args.todos)
            
            if task_id then
                -- 更新任务状态为进行中
                task.update_task_status(task_id, task.TASK_STATUS.IN_PROGRESS)
                
                return {
                    success = true,
                    task_id = task_id,
                    message = "任务创建成功，包含 " .. #args.todos .. " 个待办事项",
                    analysis = args.analysis,
                    task_description = args.task_description,
                    todos = args.todos
                }
            else
                return {
                    success = false,
                    error = "任务创建失败"
                }
            end
        end
    }
    
    -- update_task 工具
    M.builtin_tools.update_task = {
        name = "update_task",
        description = "更新任务中todo项的状态",
        parameters = {
            type = "object",
            properties = {
                task_id = {
                    type = "string",
                    description = "任务ID"
                },
                todo_id = {
                    type = "string",
                    description = "Todo项ID"
                },
                status = {
                    type = "string",
                    enum = {"pending", "in_progress", "completed", "failed", "skipped"},
                    description = "新的状态"
                },
                result = {
                    type = "string",
                    description = "执行结果或备注"
                }
            },
            required = {"task_id", "todo_id", "status"}
        },
        execute = function(args)
            utils.log("info", "执行 update_task 工具")
            
            -- 验证参数
            if not args.task_id or not args.todo_id or not args.status then
                return {
                    success = false,
                    error = "缺少必要参数"
                }
            end
            
            -- 更新todo状态
            local success = task.update_todo_status(args.task_id, args.todo_id, args.status, args.result)
            
            if success then
                -- 检查是否所有todo都已完成
                if task.are_all_todos_complete(args.task_id) then
                    task.update_task_status(args.task_id, task.TASK_STATUS.COMPLETED)
                    return {
                        success = true,
                        message = "Todo状态更新成功，所有任务已完成",
                        task_completed = true
                    }
                else
                    return {
                        success = true,
                        message = "Todo状态更新成功",
                        task_completed = false
                    }
                end
            else
                return {
                    success = false,
                    error = "Todo状态更新失败"
                }
            end
        end
    }
    
    -- finish_task 工具
    M.builtin_tools.finish_task = {
        name = "finish_task",
        description = "标记任务完成并退出执行循环",
        parameters = {
            type = "object",
            properties = {
                task_id = {
                    type = "string",
                    description = "任务ID"
                },
                summary = {
                    type = "string",
                    description = "任务完成总结"
                },
                success = {
                    type = "boolean",
                    description = "任务是否成功完成"
                }
            },
            required = {"task_id", "summary"}
        },
        execute = function(args)
            utils.log("info", "执行 finish_task 工具")
            
            -- 验证参数
            if not args.task_id or not args.summary then
                return {
                    success = false,
                    error = "缺少必要参数"
                }
            end
            
            -- 更新任务状态
            local final_status = (args.success == false) and task.TASK_STATUS.FAILED or task.TASK_STATUS.COMPLETED
            local success = task.update_task_status(args.task_id, final_status)
            
            if success then
                return {
                    success = true,
                    message = "任务已完成",
                    summary = args.summary,
                    task_completed = true
                }
            else
                return {
                    success = false,
                    error = "任务完成标记失败"
                }
            end
        end
    }
    
    -- 注册内置工具
    for name, tool in pairs(M.builtin_tools) do
        M.register_tool(tool)
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
    if M.builtin_tools[tool_name] then
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

-- 获取工具的函数调用格式
function M.get_function_call_format(tool_name)
    local tool = M.tools[tool_name]
    if not tool then
        return nil
    end
    
    return {
        name = tool.name,
        description = tool.description,
        parameters = tool.parameters
    }
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
        if M.builtin_tools[name] then
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
        if not M.builtin_tools[name] then
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
            is_builtin = M.builtin_tools[name] ~= nil,
            -- 这里可以添加更多统计信息，比如调用次数等
        }
    end
    
    return stats
end

return M 