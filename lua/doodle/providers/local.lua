-- lua/doodle/providers/local.lua
local utils = require("doodle.utils")
local base = require("doodle.providers.base")
require("doodle.types")

local M = {}

-- Local Provider类
---@class DoodleLocalProvider : DoodleBaseProvider
M.LocalProvider = {}
M.LocalProvider.__index = M.LocalProvider
setmetatable(M.LocalProvider, { __index = base.BaseProvider })

---@param config DoodleProviderConfig | DoodleCustomProviderConfig
---@return DoodleLocalProvider
function M.LocalProvider:new(config)
    config = config or {}
    
    -- Local provider专用的API key获取逻辑
    -- 本地模型通常不需要API key，但如果用户配置了就使用
    local api_key = config.local_api_key or ""
    
    -- 创建config的副本，避免修改原始对象
    local provider_config = {
        name = "local",
        description = "本地模型Provider",
        base_url = config.base_url or "http://localhost:8080/v1",
        model = config.model or "local-model",
        api_key = api_key,
        stream = config.stream or false,
        supports_functions = config.supports_functions or false,
    }
    
    local instance = base.BaseProvider:new(provider_config)
    setmetatable(instance, self)
    return instance
end

-- Local 流式请求处理（许多本地模型使用OpenAI兼容格式）
function M.LocalProvider:handle_stream_request(curl, url, data, headers, callback)
    local response_buffer = ""
    local tool_calls_aggregator = {} -- 用于聚合工具调用分片
    local response_content = ""      -- 聚合文本内容
    
    local function process_chunk(error, data)
        utils.log("dev", "[Local] process_chunk调用开始")
        
        -- 检查是否有错误
        if error then
            utils.log("error", "[Local] 流式输出错误: " .. error)
            utils.log("dev", "[Local] 错误处理: 调用callback并返回")
            callback(nil, { error = "流式输出错误: " .. error })
            return
        end
        
        -- 检查data是否为nil或空
        if not data or data == "" then
            utils.log("dev", "[Local] 数据为空，跳过处理")
            return
        end
        
        utils.log("dev", "[Local] 接收到原始数据长度: " .. #data)
        utils.log("dev", "[Local] 接收到原始数据内容: " .. vim.inspect(data))
        
        -- 直接分割当前接收到的数据
        local lines = vim.split(data, "\n")
        utils.log("dev", "[Local] 数据分割为 " .. #lines .. " 行")
        
        -- 处理每一行
        for i, line in ipairs(lines) do
            utils.log("dev", "[Local] 处理第 " .. i .. " 行: " .. vim.inspect(line))
            
            if line:match("^data: ") then
                local json_data = line:sub(7) -- 移除"data: "前缀
                utils.log("dev", "[Local] 检测到SSE数据行，JSON内容: " .. vim.inspect(json_data))
                
                if json_data == "[DONE]" then
                    utils.log("dev", "[Local] 检测到[DONE]标记，结束流式输出")
                    
                    -- 处理聚合的工具调用 - 每个工具调用单独callback
                    for _, tool_call in ipairs(tool_calls_aggregator) do
                        if tool_call.name ~= "" and tool_call.arguments ~= "" then
                            utils.log("dev", "[Local] 发送完整工具调用: " .. vim.inspect(tool_call))
                            callback(tool_call, { type = "function_call" })
                        end
                    end
                    
                    -- 处理聚合的文本内容
                    if response_content ~= "" then
                        utils.log("dev", "[Local] 发送完整文本内容: " .. vim.inspect(response_content))
                        callback(response_content, { type = "content", done = true })
                    end
                    
                    callback(nil, { done = true })
                    return
                end
                
                utils.log("dev", "[Local] 尝试解析JSON: " .. json_data)
                local success, parsed = pcall(vim.json.decode, json_data)
                if success then
                    utils.log("dev", "[Local] JSON解析成功: " .. vim.inspect(parsed))
                    
                    if parsed.choices and parsed.choices[1] and parsed.choices[1].delta then
                        local delta = parsed.choices[1].delta
                        utils.log("dev", "[Local] 提取delta数据: " .. vim.inspect(delta))
                        
                        if delta.content and delta.content ~= vim.NIL then
                            utils.log("dev", "[Local] 聚合内容数据: " .. vim.inspect(delta.content))
                            response_content = response_content .. delta.content
                            -- 实时输出内容用于用户体验
                            callback(delta.content, { type = "content" })
                        end
                        
                        -- 支持新的tool_calls格式 - 聚合分片数据
                        if delta.tool_calls then
                            utils.log("dev", "[Local] 发现工具调用数据: " .. vim.inspect(delta.tool_calls))
                            for _, tool_call_chunk in ipairs(delta.tool_calls) do
                                local index = tool_call_chunk.index or 0
                                utils.log("dev", "[Local] 处理工具调用分片，index: " .. index)
                                
                                -- 确保aggregator中有对应index的条目
                                if not tool_calls_aggregator[index + 1] then
                                    tool_calls_aggregator[index + 1] = {
                                        id = "",
                                        type = "function",
                                        name = "",
                                        arguments = ""
                                    }
                                end
                                
                                -- 聚合各部分数据
                                if tool_call_chunk.id then
                                    tool_calls_aggregator[index + 1].id = tool_call_chunk.id
                                    utils.log("dev", "[Local] 聚合工具调用ID: " .. tool_call_chunk.id)
                                end
                                
                                if tool_call_chunk["function"] then
                                    if tool_call_chunk["function"].name then
                                        tool_calls_aggregator[index + 1].name = tool_call_chunk["function"].name
                                        utils.log("dev", "[Local] 聚合工具调用名称: " .. tool_call_chunk["function"].name)
                                    end
                                    if tool_call_chunk["function"].arguments then
                                        tool_calls_aggregator[index + 1].arguments = 
                                            tool_calls_aggregator[index + 1].arguments .. tool_call_chunk["function"].arguments
                                        utils.log("dev", "[Local] 聚合工具调用参数分片: " .. tool_call_chunk["function"].arguments)
                                    end
                                end
                            end
                        end
                        
                        -- 向后兼容旧的function_call格式 - 立即callback
                        if delta.function_call then
                            utils.log("dev", "[Local] 发现旧格式函数调用: " .. vim.inspect(delta.function_call))
                            callback(delta.function_call, { type = "function_call" })
                        end
                        
                        if (not delta.content or delta.content == vim.NIL) and not delta.tool_calls and not delta.function_call then
                            utils.log("dev", "[Local] delta中没有内容或工具调用数据")
                        end
                    else
                        utils.log("dev", "[Local] JSON结构不符合预期，缺少choices/delta字段")
                    end
                else
                    utils.log("error", "[Local] JSON解析失败: " .. vim.inspect(parsed))
                end
            else
                utils.log("dev", "[Local] 跳过非SSE数据行: " .. vim.inspect(line))
            end
        end
        
        utils.log("dev", "[Local] process_chunk处理完成")
    end
    
    -- plenary.nvim的curl模块是通过job模块实现的，并且目前只需要实现流式异步返回。
    return curl.post(url, {
        headers = headers,
        body = vim.json.encode(data),
        stream = process_chunk,
        callback = function(result)
            if result.status ~= 200 then
                utils.log("error", "本地模型API请求失败: " .. result.status)
                callback(nil, { error = "API请求失败", status = result.status })
            end
        end,
    })
end

-- -- Local 同步请求处理
-- function M.LocalProvider:handle_sync_request(curl, url, data, headers, callback)
--     curl.post(url, {
--         headers = headers,
--         body = vim.json.encode(data),
--         callback = function(result)
--             if result.status == 200 then
--                 local success, parsed = pcall(vim.json.decode, result.body)
--                 if success then
--                     if parsed.choices and parsed.choices[1] then
--                         local choice = parsed.choices[1]
--                         if choice.message then
--                             -- 处理普通文本响应
--                             if choice.message.content then
--                                 callback(choice.message.content, { type = "content", done = true })
--                             end
--                             -- 支持新的tool_calls格式
--                             if choice.message.tool_calls then
--                                 for _, tool_call in ipairs(choice.message.tool_calls) do
--                                     callback(tool_call, { type = "function_call", done = true })
--                                 end
--                             end
--                             -- 向后兼容旧的function_call格式
--                             if choice.message.function_call then
--                                 callback(choice.message.function_call, { type = "function_call", done = true })
--                             end
--                         end
--                     end
--                 else
--                     utils.log("error", "本地模型响应解析失败")
--                     callback(nil, { error = "解析响应失败" })
--                 end
--             else
--                 utils.log("error", "本地模型API请求失败: " .. result.status)
--                 callback(nil, { error = "API请求失败", status = result.status })
--             end
--         end
--     })
--     
--     return true
-- end

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
        -- stream = options.stream or false,
        -- 目前只需要实现流式输出，所以设置为true
        stream = true,
        temperature = options.temperature or 0.7,
        max_tokens = options.max_tokens or 2048,
    }
    
    -- 支持工具调用：优先使用tools格式，回退到functions格式
    if options.tools then
        request_data.tools = options.tools
        request_data.tool_choice = options.tool_choice or "auto"
    elseif options.functions then
        request_data.functions = options.functions
        request_data.function_call = options.function_call or "auto"
    end
    
    -- 合并extra_body参数
    if self.extra_body and type(self.extra_body) == "table" then
        for key, value in pairs(self.extra_body) do
            request_data[key] = value
        end
    end
    
    local headers = {
        ["Content-Type"] = "application/json",
    }
    
    utils.log("debug", "发送本地模型请求: " .. self.base_url .. "/chat/completions")
    utils.log("debug", "发送本地模型请求数据: " .. vim.inspect(request_data))
    utils.log("debug", "发送本地模型Header: " .. vim.inspect(headers))
    
    -- 目前只需要实现流式输出，所以设置为true
    -- return plenary.nvim job object
    return self:handle_stream_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
    
    -- if request_data.stream then
    --     -- return plenary.nvim job object
    --     return self:handle_stream_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
    -- else
    --     -- return curl response
    --     return self:handle_sync_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
    -- end
end

-- 工厂方法
function M.create(config)
    return M.LocalProvider:new(config)
end

return M 