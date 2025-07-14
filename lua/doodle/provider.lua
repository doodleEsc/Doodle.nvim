-- lua/doodle/provider.lua
local utils = require("doodle.utils")
local providers = require("doodle.providers.init")
require("doodle.types")

---@type DoodleProviderModule
local M = {}

-- Provider注册表
M.providers = {}

-- 初始化
---@param config DoodleConfig
function M.init(config)
	M.config = config
	M.providers = {}
	utils.log("info", "Provider模块初始化完成")
end

-- 加载Provider
---@param config DoodleConfig
function M.load(config)
	M.config = config

	-- 加载内置Provider
	M.load_builtin_providers()

	-- 处理自定义Provider配置
	M.load_custom_providers(config.custom_providers or {})

	-- 将Provider存储到配置中
	config.providers = M.providers

	utils.log("info", "Provider模块加载完成，共加载 " .. M.count_providers() .. " 个Provider")
end

-- 加载内置Provider
function M.load_builtin_providers()
	-- 获取内置Provider名称列表
	local builtin_names = providers.list_builtin_providers()

	for _, name in ipairs(builtin_names) do
		-- 传递完整配置给provider，让provider自己决定如何获取API key
		local provider, error_msg = providers.create_builtin_provider(name, M.config)
		if provider then
			M.register_provider(provider)
			utils.log("info", "加载内置Provider: " .. name)
		else
			utils.log("error", "加载内置Provider失败: " .. name .. " - " .. error_msg)
		end
	end

	utils.log("info", "内置Provider加载完成")
end

-- 加载自定义Provider
-- 支持两种模式：
-- 1. 覆盖内置Provider配置：如果custom_providers中的provider名称与内置provider相同，
--    则会将用户配置与内置配置深度合并，用户配置优先级更高
-- 2. 添加新的自定义Provider：如果是全新的provider名称，则作为新provider注册
--
-- 示例配置：
-- custom_providers = {
--     -- 覆盖内置openai provider的部分配置
--     openai = {
--         model = "gpt-4",  -- 覆盖默认模型
--         base_url = "https://my-proxy.com/v1"  -- 使用代理URL
--     },
--     -- 添加全新的自定义provider
--     my_custom = {
--         name = "my_custom",
--         base_url = "https://my-api.com",
--         model = "custom-model"
--     }
-- }
---@param custom_providers DoodleCustomProvidersConfig
function M.load_custom_providers(custom_providers)
	if not custom_providers or type(custom_providers) ~= "table" then
		return
	end

	-- 获取内置Provider名称列表
	local builtin_names = providers.list_builtin_providers()
	local builtin_name_set = {}
	for _, name in ipairs(builtin_names) do
		builtin_name_set[name] = true
	end

	for name, provider_config in pairs(custom_providers) do
		if builtin_name_set[name] then
			-- 这是对内置Provider的配置覆盖
			utils.log("debug", "检测到对内置Provider的配置覆盖: " .. name)
			M.override_builtin_provider(name, provider_config)
		else
			-- 这是新的自定义Provider
			utils.log("debug", "加载新的自定义Provider: " .. name)
			local valid, error_msg = utils.validate_provider(provider_config)
			if valid then
				-- 确保provider_config有name字段
				if not provider_config.name then
					provider_config.name = name
				end
				M.register_provider(provider_config)
				utils.log("info", "成功加载自定义Provider: " .. name)
			else
				utils.log("warn", "无效的自定义Provider: " .. name .. " - " .. error_msg)
			end
		end
	end
end

-- 覆盖内置Provider的配置
-- 示例用法：
-- custom_providers = {
--     openai = {
--         model = "gpt-4",  -- 覆盖默认的 gpt-3.5-turbo
--         base_url = "https://custom-api.com/v1"  -- 覆盖默认URL
--     }
-- }
function M.override_builtin_provider(name, custom_config)
	local existing_provider = M.providers[name]
	if not existing_provider then
		utils.log("warn", "尝试覆盖不存在的内置Provider: " .. name)
		return
	end

	-- 获取现有provider的配置
	local existing_config = existing_provider.config or {}

	-- 合并配置：用户配置覆盖默认配置
	-- 使用 vim.tbl_extend("force", ...) 确保 custom_config 中的值覆盖 existing_config
	local merged_config = vim.tbl_extend("force", existing_config, custom_config)
	merged_config.name = name -- 确保名称正确

	-- 使用合并后的配置重新创建provider实例
	local new_provider, error_msg = providers.create_builtin_provider(name, merged_config)
	if new_provider then
		M.providers[name] = new_provider
		utils.log(
			"info",
			"成功覆盖内置Provider配置: " .. name .. " (模型: " .. (merged_config.model or "默认") .. ")"
		)
	else
		utils.log("error", "覆盖内置Provider失败: " .. name .. " - " .. (error_msg or "未知错误"))
	end
end

-- 注册Provider
---@param provider DoodleBaseProvider | DoodleProviderConfig
---@return boolean
function M.register_provider(provider)
	if not provider or not provider.name then
		utils.log("error", "Provider注册失败：无效的Provider对象")
		return false
	end

	-- 如果是Provider实例，直接注册
	if type(provider.validate) == "function" then
		local valid, error_msg = provider:validate()
		if not valid then
			utils.log("error", "Provider注册失败：" .. error_msg)
			return false
		end
		M.providers[provider.name] = provider
	else
		-- 如果是配置对象，需要验证
		local valid, error_msg = utils.validate_provider(provider)
		if not valid then
			utils.log("error", "Provider注册失败：" .. error_msg)
			return false
		end
		M.providers[provider.name] = provider
	end

	utils.log("debug", "注册Provider: " .. provider.name)
	return true
end

-- 获取Provider
---@param provider_name string
---@return DoodleBaseProvider?
function M.get_provider(provider_name)
	return M.providers[provider_name]
end

-- 获取当前Provider
---@return DoodleBaseProvider?
function M.get_current_provider()
	local current_name = M.config.provider
	return M.providers[current_name]
end

-- 设置当前Provider
---@param provider_name string
---@return boolean
function M.set_current_provider(provider_name)
	if not M.providers[provider_name] then
		utils.log("error", "Provider不存在: " .. provider_name)
		return false
	end

	M.config.provider = provider_name
	utils.log("info", "切换到Provider: " .. provider_name)
	return true
end

-- 发送请求的主要接口
function M.request(messages, options, callback)
	local provider = M.get_current_provider()
	if not provider then
		utils.log("error", "没有可用的Provider")
		return false
	end

	options = options or {}

	-- 工具调用支持检查
	if options.tools and not provider.supports_functions then
		utils.log("warn", "当前Provider不支持工具调用")
		options.tools = nil
	end

	utils.log("info", "使用Provider: " .. provider.name)

	-- 如果是Provider实例，调用其request方法
	if type(provider.request) == "function" then
		return provider:request(messages, options, callback)
	else
		-- 如果是配置对象，调用其request函数
		return provider.request(messages, options, callback)
	end
end

-- 列出所有Provider
---@return DoodleProviderInfo[]
function M.list_providers()
	local provider_list = {}
	for name, provider in pairs(M.providers) do
		local info
		if type(provider.get_info) == "function" then
			info = provider:get_info()
		else
			-- 为自定义provider创建脱敏的api_key显示
			local masked_api_key = nil
			if provider.api_key and provider.api_key ~= "" then
				local key = tostring(provider.api_key)
				if #key <= 8 then
					masked_api_key = "***"
				else
					local prefix = key:sub(1, 4)
					local suffix = key:sub(-4)
					local middle_length = #key - 8
					local middle = string.rep("*", math.min(middle_length, 16))
					masked_api_key = prefix .. middle .. suffix
				end
			end
			
			info = {
				name = provider.name or name,  -- 优先使用provider.name，fallback到key
				description = provider.description,
				base_url = provider.base_url,
				model = provider.model,
				api_key = masked_api_key,  -- 添加脱敏的api_key字段
				stream = provider.stream,
				supports_functions = provider.supports_functions,
				extra_body = provider.extra_body or {},  -- 添加extra_body字段
			}
		end
		table.insert(provider_list, info)
	end
	return provider_list
end

-- 检查Provider是否存在
---@param provider_name string
---@return boolean
function M.has_provider(provider_name)
	return M.providers[provider_name] ~= nil
end

-- 统计Provider数量
---@return number
function M.count_providers()
	local count = 0
	for _ in pairs(M.providers) do
		count = count + 1
	end
	return count
end

-- 获取Provider状态
---@param provider_name string
---@return DoodleProviderInfo?
function M.get_provider_status(provider_name)
	local provider = M.providers[provider_name]
	if not provider then
		return nil
	end

	local info
	if type(provider.get_info) == "function" then
		info = provider:get_info()
	else
		info = {
			name = provider.name,
			description = provider.description,
			model = provider.model,
			base_url = provider.base_url,
			stream = provider.stream,
			supports_functions = provider.supports_functions,
		}
	end

	info.available = true -- 这里可以添加健康检查逻辑
	return info
end

-- 测试Provider连接
function M.test_provider(provider_name)
	local provider = M.providers[provider_name]
	if not provider then
		return false, "Provider不存在"
	end

	-- 发送一个简单的测试请求
	local test_messages = {
		{ role = "user", content = "Hello" },
	}

	local test_options = {
		max_tokens = 10,
		stream = false,
	}

	local success = false
	local error_msg = nil

	-- 调用Provider的request方法
	local request_func = provider.request
	if type(provider.request) == "function" and provider.validate then
		request_func = function(messages, options, callback)
			return provider:request(messages, options, callback)
		end
	end

	request_func(test_messages, test_options, function(content, meta)
		if meta and meta.error then
			error_msg = meta.error
		else
			success = true
		end
	end)

	-- 等待响应（简化处理）
	vim.wait(5000, function()
		return success or error_msg
	end)

	return success, error_msg
end

-- 注销Provider
function M.unregister_provider(provider_name)
	if providers.has_builtin_provider(provider_name) then
		utils.log("warn", "不能注销内置Provider: " .. provider_name)
		return false
	end

	M.providers[provider_name] = nil
	utils.log("info", "注销Provider: " .. provider_name)
	return true
end

-- 重置Provider
function M.reset_providers()
	M.providers = {}
	M.load_builtin_providers()
	utils.log("info", "Provider重置完成")
end

-- 导出Provider数据
function M.export_provider_data()
	local export_data = {
		providers = {},
		exported_at = utils.get_timestamp(),
	}

	-- 只导出自定义Provider
	for name, provider in pairs(M.providers) do
		if not providers.has_builtin_provider(name) then
			export_data.providers[name] = provider
		end
	end

	return export_data
end

-- 导入Provider数据
function M.import_provider_data(data)
	if not data or type(data) ~= "table" or not data.providers then
		return false, "无效的导入数据"
	end

	local imported_count = 0
	for name, provider in pairs(data.providers) do
		if M.register_provider(provider) then
			imported_count = imported_count + 1
		end
	end

	utils.log("info", "导入Provider数据完成，共导入 " .. imported_count .. " 个Provider")
	return true
end

return M
