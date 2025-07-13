-- lua/doodle/providers/anthropic.lua
local utils = require("doodle.utils")
local base = require("doodle.providers.base")

local M = {}

-- Anthropic Provider类
M.AnthropicProvider = {}
M.AnthropicProvider.__index = M.AnthropicProvider
setmetatable(M.AnthropicProvider, { __index = base.BaseProvider })

function M.AnthropicProvider:new(config)
    config = config or {}
    config.name = "anthropic"
    config.description = "Anthropic Claude API Provider"
    config.base_url = config.base_url or "https://api.anthropic.com/v1"
    config.model = config.model or "claude-3-sonnet-20240229"
    config.stream = config.stream or true
    config.supports_functions = config.supports_functions or true
    
    local instance = base.BaseProvider:new(config)
    setmetatable(instance, self)
    return instance
end

-- Anthropic 流式请求处理
function M.AnthropicProvider:handle_stream_request(curl, url, data, headers, callback)
    local response_buffer = ""
    
    local function process_chunk(chunk)
        response_buffer = response_buffer .. chunk
        
        -- 处理Anthropic的Server-Sent Events格式
        for line in response_buffer:gmatch("[^\r\n]+") do
            if line:match("^event: ") then
                local event_type = line:sub(8) -- 移除"event: "前缀
                -- 获取下一行的数据
                local data_line = response_buffer:match("data: ([^\r\n]+)")
                if data_line and event_type == "completion" then
                    local success, parsed = pcall(vim.json.decode, data_line)
                    if success and parsed.completion then
                        callback(parsed.completion, { type = "content" })
                    end
                    if success and parsed.stop_reason then
                        callback(nil, { done = true, stop_reason = parsed.stop_reason })
                    end
                elseif event_type == "ping" then
                    -- 处理ping事件，保持连接活跃
                    utils.log("debug", "Anthropic ping received")
                elseif event_type == "error" then
                    -- 处理错误事件
                    local success, parsed = pcall(vim.json.decode, data_line or "{}")
                    if success and parsed.error then
                        callback(nil, { error = parsed.error.message or "Unknown error" })
                    end
                end
            end
        end
    end
    
    curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        stream = process_chunk,
        callback = function(result)
            if result.status ~= 200 then
                utils.log("error", "Anthropic API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end
    })
    
    return true
end

-- Anthropic 同步请求处理
function M.AnthropicProvider:handle_sync_request(curl, url, data, headers, callback)
    curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        callback = function(result)
            if result.status == 200 then
                local success, parsed = pcall(vim.json.decode, result.body)
                if success then
                    if parsed.completion then
                        callback(parsed.completion, { type = "content", done = true })
                    end
                    if parsed.stop_reason then
                        callback(nil, { done = true, stop_reason = parsed.stop_reason })
                    end
                else
                    utils.log("error", "Anthropic响应解析失败")
                    callback(nil, { error = "解析响应失败" })
                end
            else
                utils.log("error", "Anthropic API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end
    })
    
    return true
end

-- 转换消息格式为Anthropic格式
function M.AnthropicProvider:convert_messages_to_anthropic(messages)
    local anthropic_messages = {}
    
    for _, msg in ipairs(messages) do
        if msg.role ~= "system" then -- Anthropic在请求体中单独处理system消息
            table.insert(anthropic_messages, {
                role = msg.role,
                content = msg.content
            })
        end
    end
    
    return anthropic_messages
end

-- 实现请求方法
function M.AnthropicProvider:request(messages, options, callback)
    local plenary_ok, curl = pcall(require, "plenary.curl")
    if not plenary_ok then
        utils.log("error", "plenary.nvim 未安装")
        return false
    end
    
    local api_key = self.config.api_key or options.api_key or os.getenv("ANTHROPIC_API_KEY")
    if not api_key then
        utils.log("error", "未设置Anthropic API Key")
        return false
    end
    
    -- 转换消息格式
    local anthropic_messages = self:convert_messages_to_anthropic(messages)
    
    local request_data = {
        model = options.model or self.model,
        messages = anthropic_messages,
        stream = options.stream or false,
        max_tokens = options.max_tokens or 2048,
        temperature = options.temperature or 0.7
    }
    
    local headers = {
        ["x-api-key"] = api_key,
        ["Content-Type"] = "application/json",
        ["anthropic-version"] = "2023-06-01"
    }
    
    utils.log("debug", "发送Anthropic请求: " .. self.base_url .. "/messages")
    
    if request_data.stream then
        return self:handle_stream_request(curl, self.base_url .. "/messages", request_data, headers, callback)
    else
        return self:handle_sync_request(curl, self.base_url .. "/messages", request_data, headers, callback)
    end
end

-- 工厂方法
function M.create(config)
    return M.AnthropicProvider:new(config)
end

return M 