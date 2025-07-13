-- lua/doodle/providers/local.lua
local utils = require("doodle.utils")
local base = require("doodle.providers.base")

local M = {}

-- Local Provider类
M.LocalProvider = {}
M.LocalProvider.__index = M.LocalProvider
setmetatable(M.LocalProvider, { __index = base.BaseProvider })

function M.LocalProvider:new(config)
    config = config or {}
    config.name = "local"
    config.description = "本地模型Provider"
    config.base_url = config.base_url or "http://localhost:8080/v1"
    config.model = config.model or "local-model"
    config.stream = config.stream or false
    config.supports_functions = config.supports_functions or false
    
    local instance = base.BaseProvider:new(config)
    setmetatable(instance, self)
    return instance
end

-- Local 流式请求处理（许多本地模型使用OpenAI兼容格式）
function M.LocalProvider:handle_stream_request(curl, url, data, headers, callback)
    local response_buffer = ""
    
    local function process_chunk(chunk)
        response_buffer = response_buffer .. chunk
        
        -- 处理OpenAI兼容的Server-Sent Events格式
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
                utils.log("error", "本地模型API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end
    })
    
    return true
end

-- Local 同步请求处理
function M.LocalProvider:handle_sync_request(curl, url, data, headers, callback)
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
                    utils.log("error", "本地模型响应解析失败")
                    callback(nil, { error = "解析响应失败" })
                end
            else
                utils.log("error", "本地模型API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end
    })
    
    return true
end

-- 实现请求方法
function M.LocalProvider:request(messages, options, callback)
    local plenary_ok, curl = pcall(require, "plenary.curl")
    if not plenary_ok then
        utils.log("error", "plenary.nvim 未安装")
        return false
    end
    
    local request_data = {
        model = options.model or self.model,
        messages = messages,
        stream = options.stream or false,
        temperature = options.temperature or 0.7,
        max_tokens = options.max_tokens or 2048
    }
    
    local headers = {
        ["Content-Type"] = "application/json"
    }
    
    utils.log("debug", "发送本地模型请求: " .. self.base_url .. "/chat/completions")
    
    if request_data.stream then
        return self:handle_stream_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
    else
        return self:handle_sync_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
    end
end

-- 工厂方法
function M.create(config)
    return M.LocalProvider:new(config)
end

return M 