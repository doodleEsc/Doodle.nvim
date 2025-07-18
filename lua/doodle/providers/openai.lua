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
	local tool_calls_aggregator = {} -- 用于聚合工具调用分片
	local response_content = "" -- 聚合文本内容

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

				-- 处理流式输出结束
				if json_data == "[DONE]" then
					utils.log("dev", "[OpenAI] 检测到[DONE]标记，结束流式输出")

					-- 处理聚合的工具调用 - 每个工具调用单独callback
					for _, tool_call in ipairs(tool_calls_aggregator) do
						if tool_call.name ~= "" and tool_call.arguments ~= "" then
							utils.log("dev", "[OpenAI] 发送完整工具调用: " .. vim.inspect(tool_call))
							callback(tool_call, { type = "function_call" })
						end
					end

					-- 处理聚合的文本内容
					if response_content ~= "" then
						utils.log("dev", "[OpenAI] 发送完整文本内容: " .. vim.inspect(response_content))
						callback(response_content, { type = "content", done = true })
					end

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

						-- 处理文本内容
						if delta.content and delta.content ~= vim.NIL then
							utils.log("dev", "[OpenAI] 聚合内容数据: " .. vim.inspect(delta.content))
							response_content = response_content .. delta.content
							-- 实时输出内容用于用户体验
							callback(delta.content, { type = "content" })
						end

						-- 处理工具调用内容
						if delta.tool_calls then
							utils.log("dev", "[OpenAI] 发现工具调用数据: " .. vim.inspect(delta.tool_calls))
							for _, tool_call_chunk in ipairs(delta.tool_calls) do
								local index = tool_call_chunk.index or 0
								utils.log("dev", "[OpenAI] 处理工具调用分片，index: " .. index)

								-- 确保aggregator中有对应index的条目
								if not tool_calls_aggregator[index + 1] then
									tool_calls_aggregator[index + 1] = {
										id = "",
										type = "function",
										name = "",
										arguments = "",
									}
								end

								-- 聚合各部分数据
								if tool_call_chunk.id then
									tool_calls_aggregator[index + 1].id = tool_call_chunk.id
									utils.log("dev", "[OpenAI] 聚合工具调用ID: " .. tool_call_chunk.id)
								end

								if tool_call_chunk["function"] then
									if tool_call_chunk["function"].name then
										tool_calls_aggregator[index + 1].name = tool_call_chunk["function"].name
										utils.log(
											"dev",
											"[OpenAI] 聚合工具调用名称: " .. tool_call_chunk["function"].name
										)
									end

									if tool_call_chunk["function"].arguments then
										tool_calls_aggregator[index + 1].arguments = tool_calls_aggregator[index + 1].arguments
											.. tool_call_chunk["function"].arguments
										utils.log(
											"dev",
											"[OpenAI] 聚合工具调用参数分片: "
												.. tool_call_chunk["function"].arguments
										)
									end
								end
							end
						end

						if (not delta.content or delta.content == vim.NIL) and not delta.tool_calls then
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
    
    -- plenary.nvim的curl模块是通过job模块实现的，并且目前只需要实现流式异步返回。
	return curl.post(url, {
		headers = headers,
		body = vim.json.encode(data),
		stream = process_chunk,
		callback = function(result)
			if result.status ~= 200 then
				utils.log("error", "OpenAI API请求失败: " .. result.status)
				callback(nil, { error = "API请求失败", status = result.status })
			end
		end,
	})

end

-- -- OpenAI 同步请求处理
-- function M.OpenAIProvider:handle_sync_request(curl, url, data, headers, callback)
-- 	response = curl.post(url, {
-- 		headers = headers,
-- 		body = vim.json.encode(data),
-- 		-- callback = function(result)
-- 		-- 	if result.status == 200 then
-- 		-- 		local success, parsed = pcall(vim.json.decode, result.body)
-- 		-- 		if success then
-- 		-- 			if parsed.choices and parsed.choices[1] then
-- 		-- 				local choice = parsed.choices[1]
-- 		-- 				if choice.message then
-- 		-- 					-- 处理普通文本响应
-- 		-- 					if choice.message.content then
-- 		-- 						callback(choice.message.content, { type = "content", done = true })
-- 		-- 					end
-- 		-- 					-- 处理工具调用 (使用新的tool_calls格式)
-- 		-- 					if choice.message.tool_calls then
-- 		-- 						for _, tool_call in ipairs(choice.message.tool_calls) do
-- 		-- 							callback(tool_call, { type = "function_call", done = true })
-- 		-- 						end
-- 		-- 					end
-- 		-- 				end
-- 		-- 			end
-- 		-- 		else
-- 		-- 			utils.log("error", "OpenAI响应解析失败")
-- 		-- 			callback(nil, { error = "解析响应失败" })
-- 		-- 		end
-- 		-- 	else
-- 		-- 		utils.log("error", "OpenAI API请求失败: " .. result.status)
-- 		-- 		callback(nil, { error = "API请求失败", status = result.status })
-- 		-- 	end
-- 		-- end,
-- 	})

-- 	return response
-- end

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
		-- stream = options.stream or false,
        -- 目前只需要实现流式输出，所以设置为true
		stream = true,
		temperature = options.temperature or 0.7,
		max_tokens = options.max_tokens or 2048,
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
		["Content-Type"] = "application/json",
	}

	utils.log("debug", "发送OpenAI URL: " .. self.base_url .. "/chat/completions")
	utils.log("debug", "发送OpenAI请求: " .. vim.inspect(request_data))
	utils.log("debug", "发送OpenAI Header: " .. vim.inspect(headers))

    -- 目前只需要实现流式输出，所以设置为true
    -- return plenary.nvim job object
    return self:handle_stream_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)

	-- if request_data.stream then
    --     -- return plenary.nvim job object
	-- 	return self:handle_stream_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
	-- else
    --     -- returen curl response
	-- 	return self:handle_sync_request(curl, self.base_url .. "/chat/completions", request_data, headers, callback)
	-- end
end

-- 工厂方法
function M.create(config)
	return M.OpenAIProvider:new(config)
end

return M
