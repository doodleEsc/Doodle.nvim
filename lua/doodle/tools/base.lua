-- lua/doodle/tools/base.lua
local utils = require("doodle.utils")

local M = {}

-- 工具基类
M.BaseTool = {}
M.BaseTool.__index = M.BaseTool

function M.BaseTool:new(config)
    config = config or {}
    
    local instance = {
        name = config.name or "unnamed_tool",
        description = config.description or "No description provided",
        parameters = config.parameters or {
            type = "object",
            properties = {},
            required = {}
        },
        execute = config.execute
    }
    
    setmetatable(instance, self)
    return instance
end

-- 验证工具配置
function M.BaseTool:validate()
    if not self.name or self.name == "" then
        return false, "工具名称不能为空"
    end
    
    if not self.description or self.description == "" then
        return false, "工具描述不能为空"
    end
    
    if not self.execute or type(self.execute) ~= "function" then
        return false, "工具必须提供执行函数"
    end
    
    if not self.parameters or type(self.parameters) ~= "table" then
        return false, "工具参数定义无效"
    end
    
    return true
end

-- 验证执行参数
function M.BaseTool:validate_args(args)
    if not self.parameters then
        return true -- 如果没有参数要求，则通过验证
    end
    
    local params = self.parameters
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
                local valid, error_msg = self:validate_param_type(value, param_spec)
                if not valid then
                    return false, "参数 " .. param_name .. " " .. error_msg
                end
            end
        end
    end
    
    return true
end

-- 验证参数类型
function M.BaseTool:validate_param_type(value, param_spec)
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

-- 安全执行工具
function M.BaseTool:safe_execute(args)
    -- 验证参数
    local valid, error_msg = self:validate_args(args)
    if not valid then
        utils.log("error", "工具参数验证失败: " .. error_msg)
        return {
            success = false,
            error = "参数验证失败: " .. error_msg
        }
    end
    
    -- 执行工具
    utils.log("info", "执行工具: " .. self.name)
    local success, result = utils.safe_call(self.execute, args)
    if not success then
        utils.log("error", "工具执行失败: " .. tostring(result))
        return {
            success = false,
            error = "工具执行失败: " .. tostring(result)
        }
    end
    
    return result
end

-- 获取OpenAI tools格式
function M.BaseTool:to_openai_format()
    return {
        type = "function",
        ["function"] = {
            name = self.name,
            description = self.description,
            parameters = self.parameters
        }
    }
end

-- 获取工具信息
function M.BaseTool:get_info()
    return {
        name = self.name,
        description = self.description,
        parameters = self.parameters
    }
end

return M 