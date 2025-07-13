-- lua/doodle/providers/base.lua
local utils = require("doodle.utils")
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
M.BaseProvider = {}
M.BaseProvider.__index = M.BaseProvider

function M.BaseProvider:new(config)
    local instance = {
        name = config.name or "unknown",
        description = config.description or "未知Provider",
        base_url = config.base_url or "",
        model = config.model or "default",
        stream = config.stream or false,
        supports_functions = config.supports_functions or false,
        config = config
    }
    
    setmetatable(instance, self)
    return instance
end

-- 基础请求方法（子类必须重写）
function M.BaseProvider:request(messages, options, callback)
    error("Provider必须实现request方法")
end

-- 流式请求处理方法（子类必须重写）
function M.BaseProvider:handle_stream_request(curl, url, data, headers, callback)
    error("Provider必须实现handle_stream_request方法")
end

-- 同步请求处理方法（子类必须重写）
function M.BaseProvider:handle_sync_request(curl, url, data, headers, callback)
    error("Provider必须实现handle_sync_request方法")
end

-- 验证Provider是否有效
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
function M.BaseProvider:get_info()
    return {
        name = self.name,
        description = self.description,
        base_url = self.base_url,
        model = self.model,
        stream = self.stream,
        supports_functions = self.supports_functions
    }
end

-- 将工具转换为函数调用格式
function M.convert_tools_to_functions(tools)
    local functions = {}
    
    for _, tool in ipairs(tools) do
        table.insert(functions, {
            name = tool.name,
            description = tool.description,
            parameters = tool.parameters
        })
    end
    
    return functions
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