-- lua/doodle/providers/openai.lua
local utils = require("doodle.utils")
local base = require("doodle.providers.base")
require("doodle.types")

local M = {}

-- OpenAI Provider类
---@class DoodleOpenAIProvider : DoodleBaseProvider
M.OpenAIProvider = {}
M.OpenAIProvider.__index = M.OpenAIProvider
setmetatable(M.OpenAIProvider, { __index = base.BaseProvider })

---@param config DoodleProviderConfig | DoodleCustomProviderConfig
---@return DoodleOpenAIProvider
function M.OpenAIProvider:new(config)
    config = config or {}
    
    -- OpenAI provider专用的API key获取逻辑
    local api_key = config.openai_api_key or config.api_key or os.getenv("OPENAI_API_KEY") or ""
    
    -- 创建config的副本，避免修改原始对象
    local provider_config = {
        name = "openai",
        description = "OpenAI API Provider",
        base_url = config.base_url or "https://openrouter.ai/api/v1",
        model = config.model or "openai/gpt-4o-mini",
        api_key = api_key,
        stream = config.stream or true,
        supports_functions = config.supports_functions or true,
    }
    
    local instance = base.BaseProvider:new(provider_config)
    setmetatable(instance, self)
    return instance
end

-- OpenAI 流式请求处理
function M.OpenAIProvider:handle_stream_request(curl, url, data, headers, callback)
    local response_buffer = ""
    
    local function process_chunk(error, data)
        utils.log("dev", "[OpenAI] process_chunk调用开始")
        
        -- 检查是否有错误
        if error then
            utils.log("error", "[OpenAI] 流式输出错误: " .. error)
            utils.log("dev", "[OpenAI] 错误处理: 调用callback并返回")
            callback(nil, { error = "流式输出错误: " .. error })
            return
        end
        
        -- 检查data是否为nil或空
        if not data or data == "" then
            utils.log("dev", "[OpenAI] 数据为空，跳过处理")
            return
        end
        
        utils.log("dev", "[OpenAI] 接收到原始数据长度: " .. #data)
        utils.log("dev", "[OpenAI] 接收到原始数据内容: " .. vim.inspect(data))
        
        -- 直接分割当前接收到的数据，参考用户提供的处理方式
        local lines = vim.split(data, "\n")
        utils.log("dev", "[OpenAI] 数据分割为 " .. #lines .. " 行")
        
        -- 处理每一行
        for i, line in ipairs(lines) do
            utils.log("dev", "[OpenAI] 处理第 " .. i .. " 行: " .. vim.inspect(line))
            
            if line:match("^data: ") then
                local json_data = line:sub(7) -- 移除"data: "前缀
                utils.log("dev", "[OpenAI] 检测到SSE数据行，JSON内容: " .. vim.inspect(json_data))
                
                if json_data == "[DONE]" then
                    utils.log("dev", "[OpenAI] 检测到[DONE]标记，结束流式输出")
                    callback(nil, { done = true })
                    return
                end
                
                utils.log("dev", "[OpenAI] 尝试解析JSON: " .. json_data)
                local success, parsed = pcall(vim.json.decode, json_data)
                if success then
                    utils.log("dev", "[OpenAI] JSON解析成功: " .. vim.inspect(parsed))
                    
                    if parsed.choices and parsed.choices[1] and parsed.choices[1].delta then
                        local delta = parsed.choices[1].delta
                        utils.log("dev", "[OpenAI] 提取delta数据: " .. vim.inspect(delta))
                        
                        if delta.content then
                            utils.log("dev", "[OpenAI] 发现内容数据: " .. vim.inspect(delta.content))
                            utils.log("dev", "[OpenAI] 调用callback发送内容")
                            callback(delta.content, { type = "content" })
                        end
                        
                        -- 处理工具调用 (使用新的tool_calls格式)
                        if delta.tool_calls then
                            utils.log("dev", "[OpenAI] 发现工具调用数据: " .. vim.inspect(delta.tool_calls))
                            for j, tool_call in ipairs(delta.tool_calls) do
                                utils.log("dev", "[OpenAI] 处理工具调用 " .. j .. ": " .. vim.inspect(tool_call))
                                callback(tool_call, { type = "function_call" })
                            end
                        end
                        
                        if not delta.content and not delta.tool_calls then
                            utils.log("dev", "[OpenAI] delta中没有内容或工具调用数据")
                        end
                    else
                        utils.log("dev", "[OpenAI] JSON结构不符合预期，缺少choices/delta字段")
                    end
                else
                    utils.log("error", "[OpenAI] JSON解析失败: " .. vim.inspect(parsed))
                end
            else
                utils.log("dev", "[OpenAI] 跳过非SSE数据行: " .. vim.inspect(line))
            end
        end
        
        utils.log("dev", "[OpenAI] process_chunk处理完成")
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
                            -- 处理普通文本响应
                            if choice.message.content then
                                callback(choice.message.content, { type = "content", done = true })
                            end
                            -- 处理工具调用 (使用新的tool_calls格式)
                            if choice.message.tool_calls then
                                for _, tool_call in ipairs(choice.message.tool_calls) do
                                    callback(tool_call, { type = "function_call", done = true })
                                end
                            end
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
    
    local api_key = self:get_api_key() or options.api_key
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
    
    -- 添加工具调用支持 (使用新的tools格式而不是functions)
    if options.tools then
        request_data.tools = options.tools
        request_data.tool_choice = options.tool_choice or "auto"
    end
    
    -- 合并extra_body参数
    if self.extra_body and type(self.extra_body) == "table" then
        for key, value in pairs(self.extra_body) do
            request_data[key] = value
        end
    end
    
    local headers = {
        ["Authorization"] = "Bearer " .. api_key,
        ["Content-Type"] = "application/json"
    }

    utils.log("debug", "发送OpenAI URL: " .. self.base_url .. "/chat/completions")
    utils.log("debug", "发送OpenAI请求: " .. vim.inspect(request_data))
    utils.log("debug", "发送OpenAI Header: " .. vim.inspect(headers))
    
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