-- lua/doodle/providers/openai.lua
local utils = require("doodle.utils")
local base = require("doodle.providers.base")

local M = {}

-- OpenAI Provider类
M.OpenAIProvider = {}
M.OpenAIProvider.__index = M.OpenAIProvider
setmetatable(M.OpenAIProvider, { __index = base.BaseProvider })

function M.OpenAIProvider:new(config)
    config = config or {}
    config.name = "openai"
    config.description = "OpenAI API Provider"
    config.base_url = config.base_url or "https://api.openai.com/v1"
    config.model = config.model or "gpt-3.5-turbo"
    config.stream = config.stream or true
    config.supports_functions = config.supports_functions or true
    
    local instance = base.BaseProvider:new(config)
    setmetatable(instance, self)
    return instance
end

-- OpenAI 流式请求处理
function M.OpenAIProvider:handle_stream_request(curl, url, data, headers, callback)
    local response_buffer = ""
    
    local function process_chunk(chunk)
        response_buffer = response_buffer .. chunk
        
        -- 处理OpenAI的Server-Sent Events格式
        for line in response_buffer:gmatch("[^\r\n]+") do
            if line:match("^data: ") then
                local json_data = line:sub(7) -- 移除"data: "前缀
                
                if json_data == "[DONE]" then
                    callback(nil, { done = true })
                    return
                end
                
                local success, parsed = pcall(vim.json.decode, json_data)
                if success and parsed.choices and parsed.choices[1] and parsed.choices[1].delta then
                    local delta = parsed.choices[1].delta
                    if delta.content then
                        callback(delta.content, { type = "content" })
                    end
                    if delta.function_call then
                        callback(delta.function_call, { type = "function_call" })
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
                utils.log("error", "OpenAI API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end
    })
    
    return true
end

-- OpenAI 同步请求处理
function M.OpenAIProvider:handle_sync_request(curl, url, data, headers, callback)
    curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        callback = function(result)
            if result.status == 200 then
                local success, parsed = pcall(vim.json.decode, result.body)
                if success then
                    if parsed.choices and parsed.choices[1] then
                        local choice = parsed.choices[1]
                        if choice.message then
                            callback(choice.message.content, { type = "content", done = true })
                        end
                        if choice.message and choice.message.function_call then
                            callback(choice.message.function_call, { type = "function_call", done = true })
                        end
                    end
                else
                    utils.log("error", "OpenAI响应解析失败")
                    callback(nil, { error = "解析响应失败" })
                end
            else
                utils.log("error", "OpenAI API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end
    })
    
    return true
end

-- 实现请求方法
function M.OpenAIProvider:request(messages, options, callback)
    local plenary_ok, curl = pcall(require, "plenary.curl")
    if not plenary_ok then
        utils.log("error", "plenary.nvim 未安装")
        return false
    end
    
    local api_key = self.config.api_key or options.api_key
    if not api_key then
        utils.log("error", "未设置OpenAI API Key")
        return false
    end
    
    local request_data = {
        model = options.model or self.model,
        messages = messages,
        stream = options.stream or false,
        temperature = options.temperature or 0.7,
        max_tokens = options.max_tokens or 2048
    }
    
    -- 添加函数调用支持
    if options.functions then
        request_data.functions = options.functions
        request_data.function_call = options.function_call or "auto"
    end
    
    local headers = {
        ["Authorization"] = "Bearer " .. api_key,
        ["Content-Type"] = "application/json"
    }
    
    utils.log("debug", "发送OpenAI请求: " .. self.base_url .. "/chat/completions")
    
    if request_data.stream then
        return self:handle_stream_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
    else
        return self:handle_sync_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
    end
end

-- 工厂方法
function M.create(config)
    return M.OpenAIProvider:new(config)
end

return M 