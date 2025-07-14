-- lua/doodle/tools/init.lua
local utils = require("doodle.utils")

local M = {}

-- 内置工具模块列表
M.builtin_tool_modules = {
    "doodle.tools.think_task",
    "doodle.tools.update_task", 
    "doodle.tools.finish_task"
}

-- 工具缓存
M._tool_cache = {}

-- 加载所有内置工具
function M.load_builtin_tools()
    local tools = {}
    
    for _, module_name in ipairs(M.builtin_tool_modules) do
        local success, tool_module = pcall(require, module_name)
        if success and tool_module.create then
            local tool = tool_module.create()
            if tool then
                -- 验证工具
                local valid, error_msg = tool:validate()
                if valid then
                    tools[tool.name] = tool
                    utils.log("debug", "加载内置工具: " .. tool.name)
                else
                    utils.log("error", "内置工具验证失败 " .. tool.name .. ": " .. error_msg)
                end
            else
                utils.log("error", "内置工具创建失败: " .. module_name)
            end
        else
            utils.log("error", "无法加载内置工具模块: " .. module_name)
        end
    end
    
    M._tool_cache = tools
    utils.log("info", "内置工具加载完成，共加载 " .. M.count_builtin_tools() .. " 个工具")
    
    return tools
end

-- 获取单个内置工具
function M.get_builtin_tool(tool_name)
    if not M._tool_cache[tool_name] then
        return nil
    end
    return M._tool_cache[tool_name]
end

-- 获取所有内置工具
function M.get_all_builtin_tools()
    if next(M._tool_cache) == nil then
        M.load_builtin_tools()
    end
    return M._tool_cache
end

-- 检查是否为内置工具
function M.is_builtin_tool(tool_name)
    return M._tool_cache[tool_name] ~= nil
end

-- 统计内置工具数量
function M.count_builtin_tools()
    local count = 0
    for _ in pairs(M._tool_cache) do
        count = count + 1
    end
    return count
end

-- 列出内置工具名称
function M.list_builtin_tool_names()
    local names = {}
    for name in pairs(M._tool_cache) do
        table.insert(names, name)
    end
    return names
end

-- 获取内置工具信息
function M.get_builtin_tools_info()
    local info = {}
    for name, tool in pairs(M._tool_cache) do
        info[name] = tool:get_info()
    end
    return info
end

-- 执行内置工具
function M.execute_builtin_tool(tool_name, args)
    local tool = M.get_builtin_tool(tool_name)
    if not tool then
        return {
            success = false,
            error = "内置工具不存在: " .. tool_name
        }
    end
    
    return tool:safe_execute(args)
end

-- 获取内置工具的OpenAI格式
function M.get_builtin_tools_openai_format()
    local formats = {}
    for _, tool in pairs(M._tool_cache) do
        table.insert(formats, tool:to_openai_format())
    end
    return formats
end

-- 重新加载内置工具（用于开发调试）
function M.reload_builtin_tools()
    -- 清除模块缓存
    for _, module_name in ipairs(M.builtin_tool_modules) do
        package.loaded[module_name] = nil
    end
    
    -- 清除工具缓存
    M._tool_cache = {}
    
    -- 重新加载
    return M.load_builtin_tools()
end

-- 验证所有内置工具
function M.validate_all_builtin_tools()
    local results = {}
    
    for name, tool in pairs(M._tool_cache) do
        local valid, error_msg = tool:validate()
        results[name] = {
            valid = valid,
            error = error_msg
        }
    end
    
    return results
end

return M 