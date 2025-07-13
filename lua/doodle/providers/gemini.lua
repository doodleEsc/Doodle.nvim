-- lua/doodle/providers/gemini.lua
local utils = require("doodle.utils")
local base = require("doodle.providers.base")

local M = {}

-- Gemini Provider类
M.GeminiProvider = {}
M.GeminiProvider.__index = M.GeminiProvider
setmetatable(M.GeminiProvider, { __index = base.BaseProvider })

function M.GeminiProvider:new(config)
    config = config or {}
    config.name = "gemini"
    config.description = "Google Gemini API Provider"
    config.base_url = config.base_url or "https://generativelanguage.googleapis.com/v1beta"
    config.model = config.model or "gemini-pro"
    config.stream = config.stream or true
    config.supports_functions = config.supports_functions or true
    
    local instance = base.BaseProvider:new(config)
    setmetatable(instance, self)
    return instance
end

-- Gemini 流式请求处理
function M.GeminiProvider:handle_stream_request(curl, url, data, headers, callback)
    local response_buffer = ""
    
    local function process_chunk(chunk)
        response_buffer = response_buffer .. chunk
        
        -- 处理 Gemini 的流式响应格式
        for line in response_buffer:gmatch("[^\r\n]+") do
            if line:match("^data: ") then
                local json_data = line:sub(7) -- 移除"data: "前缀
                
                -- 跳过空行和ping
                if json_data == "" or json_data == "ping" then
                    goto continue
                end
                
                local success, parsed = pcall(vim.json.decode, json_data)
                if success and parsed.candidates then
                    local candidate = parsed.candidates[1]
                    if candidate and candidate.content and candidate.content.parts then
                        local part = candidate.content.parts[1]
                        if part and part.text then
                            callback(part.text, { type = "content" })
                        end
                    end
                    
                    -- 检查是否完成
                    if candidate and candidate.finishReason then
                        callback(nil, { done = true, finish_reason = candidate.finishReason })
                    end
                elseif success and parsed.error then
                    callback(nil, { error = parsed.error.message or "Unknown error" })
                end
            end
            ::continue::
        end
    end
    
    curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        stream = process_chunk,
        callback = function(result)
            if result.status ~= 200 then
                utils.log("error", "Gemini API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end
    })
    
    return true
end

-- Gemini 同步请求处理
function M.GeminiProvider:handle_sync_request(curl, url, data, headers, callback)
    curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        callback = function(result)
            if result.status == 200 then
                local success, parsed = pcall(vim.json.decode, result.body)
                if success then
                    if parsed.candidates and parsed.candidates[1] then
                        local candidate = parsed.candidates[1]
                        if candidate.content and candidate.content.parts and candidate.content.parts[1] then
                            local part = candidate.content.parts[1]
                            if part.text then
                                callback(part.text, { 
                                    type = "content", 
                                    done = true, 
                                    finish_reason = candidate.finishReason 
                                })
                            end
                        end
                    end
                    
                    if parsed.error then
                        callback(nil, { error = parsed.error.message or "Unknown error" })
                    end
                else
                    utils.log("error", "Gemini响应解析失败")
                    callback(nil, { error = "解析响应失败" })
                end
            else
                utils.log("error", "Gemini API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end
    })
    
    return true
end

-- 转换消息格式为Gemini格式
function M.GeminiProvider:convert_messages_to_gemini(messages)
    local gemini_contents = {}
    
    for _, msg in ipairs(messages) do
        local role = msg.role
        -- Gemini 使用 "user" 和 "model" 作为角色
        if role == "assistant" then
            role = "model"
        elseif role == "system" then
            -- 系统消息转换为用户消息
            role = "user"
        end
        
        table.insert(gemini_contents, {
            role = role,
            parts = {
                { text = msg.content }
            }
        })
    end
    
    return gemini_contents
end

-- 构建请求URL
function M.GeminiProvider:build_request_url(model, api_key, stream)
    local endpoint = stream and "streamGenerateContent" or "generateContent"
    return string.format("%s/models/%s:%s?key=%s", 
        self.base_url, model, endpoint, api_key)
end

-- 实现请求方法
function M.GeminiProvider:request(messages, options, callback)
    local plenary_ok, curl = pcall(require, "plenary.curl")
    if not plenary_ok then
        utils.log("error", "plenary.nvim 未安装")
        return false
    end
    
    local api_key = self.config.api_key or options.api_key or os.getenv("GEMINI_API_KEY")
    if not api_key then
        utils.log("error", "未设置Gemini API Key")
        return false
    end
    
    local model = options.model or self.model
    local stream = options.stream or false
    
    -- 转换消息格式
    local gemini_contents = self:convert_messages_to_gemini(messages)
    
    local request_data = {
        contents = gemini_contents,
        generationConfig = {
            temperature = options.temperature or 0.9,
            topK = options.top_k or 1,
            topP = options.top_p or 1,
            maxOutputTokens = options.max_tokens or 2048,
            candidateCount = 1
        },
        safetySettings = {
            {
                category = "HARM_CATEGORY_HARASSMENT",
                threshold = "BLOCK_MEDIUM_AND_ABOVE"
            },
            {
                category = "HARM_CATEGORY_HATE_SPEECH", 
                threshold = "BLOCK_MEDIUM_AND_ABOVE"
            },
            {
                category = "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                threshold = "BLOCK_MEDIUM_AND_ABOVE"
            },
            {
                category = "HARM_CATEGORY_DANGEROUS_CONTENT",
                threshold = "BLOCK_MEDIUM_AND_ABOVE"
            }
        }
    }
    
    -- 添加函数调用支持 (如果 Gemini 支持)
    if options.functions then
        request_data.tools = {
            function_declarations = options.functions
        }
    end
    
    local headers = {
        ["Content-Type"] = "application/json"
    }
    
    local url = self:build_request_url(model, api_key, stream)
    
    utils.log("debug", "发送Gemini请求: " .. url)
    
    if stream then
        return self:handle_stream_request(curl, url, request_data, headers, callback)
    else
        return self:handle_sync_request(curl, url, request_data, headers, callback)
    end
end

-- 工厂方法
function M.create(config)
    return M.GeminiProvider:new(config)
end

return M 