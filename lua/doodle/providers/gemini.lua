-- lua/doodle/providers/gemini.lua
local utils = require("doodle.utils")
local base = require("doodle.providers.base")
require("doodle.types")

local M = {}

-- Gemini Provider类
---@class DoodleGeminiProvider : DoodleBaseProvider
M.GeminiProvider = {}
M.GeminiProvider.__index = M.GeminiProvider
setmetatable(M.GeminiProvider, { __index = base.BaseProvider })

---@param config DoodleProviderConfig | DoodleCustomProviderConfig
---@return DoodleGeminiProvider
function M.GeminiProvider:new(config)
    config = config or {}
    
    -- Gemini provider专用的API key获取逻辑
    local api_key = config.gemini_api_key or os.getenv("GEMINI_API_KEY") or ""
    
    -- 创建config的副本，避免修改原始对象
    local provider_config = {
        name = "gemini",
        description = "Google Gemini API Provider",
        base_url = config.base_url or "https://generativelanguage.googleapis.com/v1beta",
        model = config.model or "gemini-pro",
        api_key = api_key,
        stream = config.stream or true,
        supports_functions = config.supports_functions or true,
    }
    
    local instance = base.BaseProvider:new(provider_config)
    setmetatable(instance, self)
    return instance
end

-- Gemini 流式请求处理
function M.GeminiProvider:handle_stream_request(curl, url, data, headers, callback)
    local tool_calls_aggregator = {} -- 用于聚合工具调用分片
    local response_content = ""      -- 聚合文本内容
    
    local function process_chunk(error, data)
        utils.log("dev", "[Gemini] process_chunk调用开始")
        
        -- 检查是否有错误
        if error then
            utils.log("error", "[Gemini] 流式输出错误: " .. error)
            utils.log("dev", "[Gemini] 错误处理: 调用callback并返回")
            callback(nil, { error = "流式输出错误: " .. error })
            return
        end
        
        -- 检查data是否为nil或空
        if not data or data == "" then
            utils.log("dev", "[Gemini] 数据为空，跳过处理")
            return
        end
        
        utils.log("dev", "[Gemini] 接收到原始数据长度: " .. #data)
        utils.log("dev", "[Gemini] 接收到原始数据内容: " .. vim.inspect(data))
        
        -- 直接分割当前接收到的数据
        local lines = vim.split(data, "\n")
        utils.log("dev", "[Gemini] 数据分割为 " .. #lines .. " 行")
        
        -- 处理每一行
        for i, line in ipairs(lines) do
            utils.log("dev", "[Gemini] 处理第 " .. i .. " 行: " .. vim.inspect(line))
            
            if line:match("^data: ") then
                local json_data = line:sub(7) -- 移除"data: "前缀
                utils.log("dev", "[Gemini] 检测到SSE数据行，JSON内容: " .. vim.inspect(json_data))
                
                -- 跳过空行和ping
                if json_data == "" or json_data == "ping" then
                    utils.log("dev", "[Gemini] 跳过空行或ping消息")
                    goto continue
                end
                
                utils.log("dev", "[Gemini] 尝试解析JSON: " .. json_data)
                local success, parsed = pcall(vim.json.decode, json_data)
                if success then
                    utils.log("dev", "[Gemini] JSON解析成功: " .. vim.inspect(parsed))
                    
                    if parsed.candidates then
                        local candidate = parsed.candidates[1]
                        utils.log("dev", "[Gemini] 提取candidate数据: " .. vim.inspect(candidate))
                        
                        if candidate and candidate.content and candidate.content.parts then
                            utils.log("dev", "[Gemini] 处理 " .. #candidate.content.parts .. " 个parts")
                            
                            for j, part in ipairs(candidate.content.parts) do
                                utils.log("dev", "[Gemini] 处理part " .. j .. ": " .. vim.inspect(part))
                                
                                -- 处理文本内容
                                if part.text then
                                    utils.log("dev", "[Gemini] 聚合文本数据: " .. vim.inspect(part.text))
                                    response_content = response_content .. part.text
                                    -- 实时输出内容用于用户体验
                                    callback(part.text, { type = "content" })
                                end
                                
                                -- 处理函数调用 - 聚合到aggregator中
                                if part.functionCall then
                                    utils.log("dev", "[Gemini] 发现函数调用数据: " .. vim.inspect(part.functionCall))
                                    
                                    -- Gemini通常不分片工具调用，但我们还是实现聚合机制
                                    local index = #tool_calls_aggregator + 1
                                    tool_calls_aggregator[index] = {
                                        id = utils.generate_uuid(),
                                        type = "function",
                                        name = part.functionCall.name,
                                        arguments = vim.json.encode(part.functionCall.args or {})
                                    }
                                    utils.log("dev", "[Gemini] 聚合工具调用到索引: " .. index)
                                end
                                
                                if not part.text and not part.functionCall then
                                    utils.log("dev", "[Gemini] part中没有文本或函数调用数据")
                                end
                            end
                        end
                        
                        -- 检查是否完成
                        if candidate and candidate.finishReason then
                            utils.log("dev", "[Gemini] 检测到完成原因: " .. candidate.finishReason)
                            
                            -- 处理聚合的工具调用 - 每个工具调用单独callback
                            for _, tool_call in ipairs(tool_calls_aggregator) do
                                if tool_call.name ~= "" and tool_call.arguments ~= "" then
                                    utils.log("dev", "[Gemini] 发送完整工具调用: " .. vim.inspect(tool_call))
                                    callback(tool_call, { type = "function_call" })
                                end
                            end
                            
                            callback(nil, { done = true, finish_reason = candidate.finishReason })
                        end
                    else
                        utils.log("dev", "[Gemini] JSON结构不符合预期，缺少candidates字段")
                    end
                    
                    if parsed.error then
                        utils.log("error", "[Gemini] API返回错误: " .. (parsed.error.message or "Unknown error"))
                        callback(nil, { error = parsed.error.message or "Unknown error" })
                    end
                else
                    utils.log("error", "[Gemini] JSON解析失败: " .. vim.inspect(parsed))
                end
            else
                utils.log("dev", "[Gemini] 跳过非SSE数据行: " .. vim.inspect(line))
            end
            ::continue::
        end
        
        utils.log("dev", "[Gemini] process_chunk处理完成")
    end
    
    -- plenary.nvim的curl模块是通过job模块实现的，并且目前只需要实现流式异步返回。
    return curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        stream = process_chunk,
        callback = function(result)
            if result.status ~= 200 then
                utils.log("error", "Gemini API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end,
    })
end

-- -- Gemini 同步请求处理
-- function M.GeminiProvider:handle_sync_request(curl, url, data, headers, callback)
--     curl.post(url, {
--         headers = headers,
--         body = vim.json.encode(data),
--         callback = function(result)
--             if result.status == 200 then
--                 local success, parsed = pcall(vim.json.decode, result.body)
--                 if success then
--                     if parsed.candidates and parsed.candidates[1] then
--                         local candidate = parsed.candidates[1]
--                         if candidate.content and candidate.content.parts then
--                             for _, part in ipairs(candidate.content.parts) do
--                                 -- 处理文本内容
--                                 if part.text then
--                                     callback(part.text, { 
--                                         type = "content", 
--                                         done = true, 
--                                         finish_reason = candidate.finishReason 
--                                     })
--                                 end
--                                 -- 处理函数调用 (转换为OpenAI格式)
--                                 if part.functionCall then
--                                     local tool_call = {
--                                         id = utils.generate_uuid(),
--                                         type = "function",
--                                         ["function"] = {
--                                             name = part.functionCall.name,
--                                             arguments = vim.json.encode(part.functionCall.args or {})
--                                         }
--                                     }
--                                     callback(tool_call, { type = "function_call", done = true })
--                                 end
--                             end
--                         end
--                     end
--                     
--                     if parsed.error then
--                         callback(nil, { error = parsed.error.message or "Unknown error" })
--                     end
--                 else
--                     utils.log("error", "Gemini响应解析失败")
--                     callback(nil, { error = "解析响应失败" })
--                 end
--             else
--                 utils.log("error", "Gemini API请求失败: " .. result.status)
--                 callback(nil, { error = "API请求失败", status = result.status })
--             end
--         end
--     })
--     
--     return true
-- end

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

-- 转换OpenAI tools格式到Gemini function_declarations格式
function M.GeminiProvider:convert_tools_to_gemini(tools)
    local function_declarations = {}
    
    for _, tool in ipairs(tools) do
        if tool.type == "function" and tool["function"] then
            table.insert(function_declarations, {
                name = tool["function"].name,
                description = tool["function"].description,
                parameters = tool["function"].parameters
            })
        end
    end
    
    return function_declarations
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
    
    local api_key = self:get_api_key() or options.api_key
    if not api_key then
        utils.log("error", "未设置Gemini API Key")
        return false
    end
    
    local model = options.model or self.model
    -- local stream = options.stream or false
    -- 目前只需要实现流式输出，所以设置为true
    local stream = true
    
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
    
    -- 添加工具调用支持 (转换OpenAI tools格式到Gemini格式)
    if options.tools then
        request_data.tools = {
            function_declarations = self:convert_tools_to_gemini(options.tools)
        }
        
        -- 添加 tool_choice 支持 (转换为 Gemini tool_config)
        if options.tool_choice and options.tool_choice ~= "auto" then
            request_data.tool_config = {
                function_calling_config = {}
            }
            
            if options.tool_choice == "none" then
                request_data.tool_config.function_calling_config.mode = "none"
            elseif type(options.tool_choice) == "string" then
                -- 如果是字符串，表示特定工具名称，使用 "any" 模式
                request_data.tool_config.function_calling_config.mode = "any"
                request_data.tool_config.function_calling_config.allowed_function_names = {options.tool_choice}
            elseif type(options.tool_choice) == "table" then
                -- 如果是表，可能是 OpenAI 格式，需要转换
                if options.tool_choice.type == "function" and options.tool_choice["function"] then
                    request_data.tool_config.function_calling_config.mode = "any"
                    request_data.tool_config.function_calling_config.allowed_function_names = {options.tool_choice["function"].name}
                elseif options.tool_choice.mode then
                    -- 直接指定模式
                    request_data.tool_config.function_calling_config.mode = options.tool_choice.mode
                    if options.tool_choice.allowed_function_names then
                        request_data.tool_config.function_calling_config.allowed_function_names = options.tool_choice.allowed_function_names
                    end
                end
            else
                -- 其他情况，强制使用函数
                request_data.tool_config.function_calling_config.mode = "any"
            end
        end
    end
    
    -- 合并extra_body参数
    if self.extra_body and type(self.extra_body) == "table" then
        for key, value in pairs(self.extra_body) do
            request_data[key] = value
        end
    end
    
    local headers = {
        ["Content-Type"] = "application/json"
    }
    
    local url = self:build_request_url(model, api_key, stream)
    
    utils.log("debug", "发送Gemini请求: " .. url)
    utils.log("debug", "发送Gemini请求数据: " .. vim.inspect(request_data))
    utils.log("debug", "发送Gemini Header: " .. vim.inspect(headers))
    
    -- 目前只需要实现流式输出，所以设置为true
    -- return plenary.nvim job object
    return self:handle_stream_request(curl, url, request_data, headers, callback)
    
    -- if stream then
    --     -- return plenary.nvim job object
    --     return self:handle_stream_request(curl, url, request_data, headers, callback)
    -- else
    --     -- return curl response
    --     return self:handle_sync_request(curl, url, request_data, headers, callback)
    -- end
end

-- 工厂方法
function M.create(config)
    return M.GeminiProvider:new(config)
end

return M 