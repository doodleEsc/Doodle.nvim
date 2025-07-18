-- lua/doodle/providers/anthropic.lua
local utils = require("doodle.utils")
local base = require("doodle.providers.base")
require("doodle.types")

local M = {}

-- Anthropic Provider类
---@class DoodleAnthropicProvider : DoodleBaseProvider
M.AnthropicProvider = {}
M.AnthropicProvider.__index = M.AnthropicProvider
setmetatable(M.AnthropicProvider, { __index = base.BaseProvider })

---@param config DoodleProviderConfig | DoodleCustomProviderConfig
---@return DoodleAnthropicProvider
function M.AnthropicProvider:new(config)
    config = config or {}
    
    -- Anthropic provider专用的API key获取逻辑
    local api_key = config.anthropic_api_key or os.getenv("ANTHROPIC_API_KEY") or ""
    
    -- 创建config的副本，避免修改原始对象
    local provider_config = {
        name = "anthropic",
        description = "Anthropic Claude API Provider",
        base_url = config.base_url or "https://api.anthropic.com/v1",
        model = config.model or "claude-3-sonnet-20240229",
        api_key = api_key,
        stream = config.stream or true,
        supports_functions = config.supports_functions or true,
    }
    
    local instance = base.BaseProvider:new(provider_config)
    setmetatable(instance, self)
    return instance
end

-- Anthropic 流式请求处理
function M.AnthropicProvider:handle_stream_request(curl, url, data, headers, callback)
    local tool_calls_aggregator = {} -- 用于聚合工具调用分片
    local response_content = ""      -- 聚合文本内容
    
    local function process_chunk(error, data)
        utils.log("dev", "[Anthropic] process_chunk调用开始")
        
        -- 检查是否有错误
        if error then
            utils.log("error", "[Anthropic] 流式输出错误: " .. error)
            utils.log("dev", "[Anthropic] 错误处理: 调用callback并返回")
            callback(nil, { error = "流式输出错误: " .. error })
            return
        end
        
        -- 检查data是否为nil或空
        if not data or data == "" then
            utils.log("dev", "[Anthropic] 数据为空，跳过处理")
            return
        end
        
        utils.log("dev", "[Anthropic] 接收到原始数据长度: " .. #data)
        utils.log("dev", "[Anthropic] 接收到原始数据内容: " .. vim.inspect(data))
        
        -- 直接分割当前接收到的数据
        local lines = vim.split(data, "\n")
        utils.log("dev", "[Anthropic] 数据分割为 " .. #lines .. " 行")
        
        -- 处理每一行
        for i, line in ipairs(lines) do
            utils.log("dev", "[Anthropic] 处理第 " .. i .. " 行: " .. vim.inspect(line))
            
            if line:match("^data: ") then
                local json_data = line:sub(7) -- 移除"data: "前缀
                utils.log("dev", "[Anthropic] 检测到SSE数据行，JSON内容: " .. vim.inspect(json_data))
                
                if json_data == "[DONE]" then
                    utils.log("dev", "[Anthropic] 检测到[DONE]标记，结束流式输出")
                    
                    -- 处理聚合的工具调用 - 每个工具调用单独callback
                    for _, tool_call in ipairs(tool_calls_aggregator) do
                        if tool_call.name ~= "" and tool_call.arguments ~= "" then
                            utils.log("dev", "[Anthropic] 发送完整工具调用: " .. vim.inspect(tool_call))
                            callback(tool_call, { type = "function_call" })
                        end
                    end
                    
                    callback(nil, { done = true })
                    return
                end
                
                utils.log("dev", "[Anthropic] 尝试解析JSON: " .. json_data)
                local success, parsed = pcall(vim.json.decode, json_data)
                if success then
                    utils.log("dev", "[Anthropic] JSON解析成功: " .. vim.inspect(parsed))
                    
                    -- 处理内容增量
                    if parsed.delta and parsed.delta.text then
                        utils.log("dev", "[Anthropic] 聚合文本数据: " .. vim.inspect(parsed.delta.text))
                        response_content = response_content .. parsed.delta.text
                        -- 实时输出内容用于用户体验
                        callback(parsed.delta.text, { type = "content" })
                    end
                    
                    -- 处理工具使用 - 聚合到aggregator中
                    if parsed.delta and parsed.delta.tool_use then
                        local tool_use = parsed.delta.tool_use
                        utils.log("dev", "[Anthropic] 发现工具使用数据: " .. vim.inspect(tool_use))
                        
                        -- Anthropic通常不分片工具调用，但我们还是实现聚合机制
                        local index = #tool_calls_aggregator + 1
                        tool_calls_aggregator[index] = {
                            id = tool_use.id or utils.generate_uuid(),
                            type = "function",
                            name = tool_use.name,
                            arguments = vim.json.encode(tool_use.input or {})
                        }
                        utils.log("dev", "[Anthropic] 聚合工具调用到索引: " .. index)
                    end
                    
                    -- 处理完成
                    if parsed.stop_reason then
                        utils.log("dev", "[Anthropic] 检测到停止原因: " .. parsed.stop_reason)
                        
                        -- 处理聚合的工具调用 - 每个工具调用单独callback
                        for _, tool_call in ipairs(tool_calls_aggregator) do
                            if tool_call.name ~= "" and tool_call.arguments ~= "" then
                                utils.log("dev", "[Anthropic] 发送完整工具调用: " .. vim.inspect(tool_call))
                                callback(tool_call, { type = "function_call" })
                            end
                        end
                        
                        callback(nil, { done = true, stop_reason = parsed.stop_reason })
                    end
                    
                    -- 处理错误
                    if parsed.error then
                        utils.log("error", "[Anthropic] API返回错误: " .. (parsed.error.message or "Unknown error"))
                        callback(nil, { error = parsed.error.message or "Unknown error" })
                    end
                    
                    if not (parsed.delta and (parsed.delta.text or parsed.delta.tool_use)) and not parsed.stop_reason and not parsed.error then
                        utils.log("dev", "[Anthropic] JSON数据中没有可处理的内容")
                    end
                else
                    utils.log("error", "[Anthropic] JSON解析失败: " .. vim.inspect(parsed))
                end
            else
                utils.log("dev", "[Anthropic] 跳过非SSE数据行: " .. vim.inspect(line))
            end
        end
        
        utils.log("dev", "[Anthropic] process_chunk处理完成")
    end
    
    -- plenary.nvim的curl模块是通过job模块实现的，并且目前只需要实现流式异步返回。
    return curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        stream = process_chunk,
        callback = function(result)
            if result.status ~= 200 then
                utils.log("error", "Anthropic API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end,
    })
end

-- -- Anthropic 同步请求处理
-- function M.AnthropicProvider:handle_sync_request(curl, url, data, headers, callback)
--     curl.post(url, {
--         headers = headers,
--         body = vim.json.encode(data),
--         callback = function(result)
--             if result.status == 200 then
--                 local success, parsed = pcall(vim.json.decode, result.body)
--                 if success then
--                     -- 处理内容
--                     if parsed.content then
--                         for _, content in ipairs(parsed.content) do
--                             if content.type == "text" then
--                                 callback(content.text, { type = "content", done = true })
--                             elseif content.type == "tool_use" then
--                                 local tool_call = {
--                                     id = content.id,
--                                     type = "function",
--                                     ["function"] = {
--                                         name = content.name,
--                                         arguments = vim.json.encode(content.input or {})
--                                     }
--                                 }
--                                 callback(tool_call, { type = "function_call", done = true })
--                             end
--                         end
--                     end
--                     
--                     -- 处理旧格式的completion（向后兼容）
--                     if parsed.completion then
--                         callback(parsed.completion, { type = "content", done = true })
--                     end
--                     
--                     if parsed.stop_reason then
--                         callback(nil, { done = true, stop_reason = parsed.stop_reason })
--                     end
--                     
--                     if parsed.error then
--                         callback(nil, { error = parsed.error.message or "Unknown error" })
--                     end
--                 else
--                     utils.log("error", "Anthropic响应解析失败")
--                     callback(nil, { error = "解析响应失败" })
--                 end
--             else
--                 utils.log("error", "Anthropic API请求失败: " .. result.status)
--                 callback(nil, { error = "API请求失败", status = result.status })
--             end
--         end
--     })
--     
--     return true
-- end

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

-- 转换OpenAI tools格式到Anthropic格式
function M.AnthropicProvider:convert_tools_to_anthropic(tools)
    local anthropic_tools = {}
    
    for _, tool in ipairs(tools) do
        if tool.type == "function" and tool["function"] then
            table.insert(anthropic_tools, {
                name = tool["function"].name,
                description = tool["function"].description,
                input_schema = tool["function"].parameters
            })
        end
    end
    
    return anthropic_tools
end

-- 实现请求方法
function M.AnthropicProvider:request(messages, options, callback)
    local plenary_ok, curl = pcall(require, "plenary.curl")
    if not plenary_ok then
        utils.log("error", "plenary.nvim 未安装")
        return false
    end
    
    local api_key = self:get_api_key() or options.api_key
    if not api_key then
        utils.log("error", "未设置Anthropic API Key")
        return false
    end
    
    -- 转换消息格式
    local anthropic_messages = self:convert_messages_to_anthropic(messages)
    
    local request_data = {
        model = options.model or self.model,
        messages = anthropic_messages,
        -- stream = options.stream or false,
        -- 目前只需要实现流式输出，所以设置为true
        stream = true,
        max_tokens = options.max_tokens or 2048,
        temperature = options.temperature or 0.7
    }
    
    -- 添加工具调用支持 (转换OpenAI tools格式到Anthropic格式)
    if options.tools then
        request_data.tools = self:convert_tools_to_anthropic(options.tools)
        
        -- 添加 tool_choice 支持
        if options.tool_choice and options.tool_choice ~= "auto" then
            if type(options.tool_choice) == "string" then
                -- 如果是字符串，表示工具名称
                request_data.tool_choice = {
                    type = "tool",
                    name = options.tool_choice
                }
            elseif type(options.tool_choice) == "table" then
                -- 如果是表，可能是 OpenAI 格式，需要转换
                if options.tool_choice.type == "function" and options.tool_choice["function"] then
                    request_data.tool_choice = {
                        type = "tool",
                        name = options.tool_choice["function"].name
                    }
                elseif options.tool_choice.type == "tool" then
                    -- 已经是 Anthropic 格式
                    request_data.tool_choice = options.tool_choice
                end
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
        ["x-api-key"] = api_key,
        ["Content-Type"] = "application/json",
        ["anthropic-version"] = "2023-06-01"
    }
    
    utils.log("debug", "发送Anthropic请求: " .. self.base_url .. "/messages")
    utils.log("debug", "发送Anthropic请求数据: " .. vim.inspect(request_data))
    utils.log("debug", "发送Anthropic Header: " .. vim.inspect(headers))
    
    -- 目前只需要实现流式输出，所以设置为true
    -- return plenary.nvim job object
    return self:handle_stream_request(curl, self.base_url .. "/messages", request_data, headers, callback)
    
    -- if request_data.stream then
    --     -- return plenary.nvim job object
    --     return self:handle_stream_request(curl, self.base_url .. "/messages", request_data, headers, callback)
    -- else
    --     -- return curl response
    --     return self:handle_sync_request(curl, self.base_url .. "/messages", request_data, headers, callback)
    -- end
end

-- 工厂方法
function M.create(config)
    return M.AnthropicProvider:new(config)
end

return M 