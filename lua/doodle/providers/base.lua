-- lua/doodle/providers/base.lua
local utils = require("doodle.utils")
require("doodle.types")
local M = {}

-- Provider接口规范
-- 每个Provider都需要实现以下属性和方法：
-- name: provider名称
-- description: provider描述
-- base_url: API基础URL
-- model: 默认模型
-- request: 请求方法（核心接口）
-- stream: 是否支持流式响应
-- supports_functions: 是否支持函数调用

-- 基础Provider类
---@class DoodleBaseProvider
M.BaseProvider = {}
M.BaseProvider.__index = M.BaseProvider

---@param config DoodleProviderConfig
---@return DoodleBaseProvider
function M.BaseProvider:new(config)
    local instance = {
        name = config.name or "unknown",
        description = config.description or "未知Provider",
        base_url = config.base_url or "",
        model = config.model or "default",
        api_key = config.api_key or "",  -- 添加api_key字段
        stream = config.stream or false,
        supports_functions = config.supports_functions or false,
        extra_body = config.extra_body or {},  -- 添加extra_body字段
        config = config
    }
    
    setmetatable(instance, self)
    return instance
end

-- 基础请求方法（子类必须重写）
---@param messages DoodleMessage[]
---@param options DoodleRequestOptions
---@param callback function
---@return boolean
function M.BaseProvider:request(messages, options, callback)
    error("Provider必须实现request方法")
end

-- 流式请求处理方法（子类必须重写）
---@param curl any
---@param url string
---@param data table
---@param headers table
---@param callback function
---@return boolean
function M.BaseProvider:handle_stream_request(curl, url, data, headers, callback)
    error("Provider必须实现handle_stream_request方法")
end

-- 同步请求处理方法（子类必须重写）
---@param curl any
---@param url string
---@param data table
---@param headers table
---@param callback function
---@return boolean
function M.BaseProvider:handle_sync_request(curl, url, data, headers, callback)
    error("Provider必须实现handle_sync_request方法")
end

-- 验证Provider是否有效
---@return boolean, string?
function M.BaseProvider:validate()
    if not self.name or self.name == "" then
        return false, "Provider名称不能为空"
    end
    
    if not self.request or type(self.request) ~= "function" then
        return false, "Provider必须实现request方法"
    end
    
    if not self.base_url or self.base_url == "" then
        return false, "Provider必须指定base_url"
    end
    
    return true, nil
end

-- 获取Provider信息
---@return DoodleProviderInfo
function M.BaseProvider:get_info()
    return {
        name = self.name,
        description = self.description,
        base_url = self.base_url,
        model = self.model,
        api_key = self:get_masked_api_key(),  -- 添加脱敏的api_key字段
        stream = self.stream,
        supports_functions = self.supports_functions,
        extra_body = self.extra_body  -- 添加extra_body字段
    }
end

-- 获取脱敏的API Key（用于显示）
---@return string
function M.BaseProvider:get_masked_api_key()
    if not self.api_key or self.api_key == "" then
        return ""
    end
    
    local key = tostring(self.api_key)
    if #key <= 8 then
        return "***"
    end
    
    -- 显示前4位和后4位，中间用*号替代
    local prefix = key:sub(1, 4)
    local suffix = key:sub(-4)
    local middle_length = #key - 8
    local middle = string.rep("*", math.min(middle_length, 16))
    
    return prefix .. middle .. suffix
end

-- 获取完整的API Key（用于实际请求）
---@return string
function M.BaseProvider:get_api_key()
    return self.api_key
end

-- 通用的HTTP请求辅助函数
function M.make_http_request(curl, url, data, headers, callback)
    curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        callback = callback
    })
end

return M 