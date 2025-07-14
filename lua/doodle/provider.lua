-- lua/doodle/provider.lua
local utils = require("doodle.utils")
local providers = require("doodle.providers.init")

local M = {}

-- Provider注册表
M.providers = {}

-- 初始化
function M.init(config)
    M.config = config
    M.providers = {}
    utils.log("info", "Provider模块初始化完成")
end

-- 加载Provider
function M.load(config)
    M.config = config
    
    -- 加载内置Provider
    M.load_builtin_providers()
    
    -- 加载自定义Provider
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
function M.load_custom_providers(custom_providers)
    if not custom_providers or type(custom_providers) ~= "table" then
        return
    end
    
    for name, provider_config in pairs(custom_providers) do
        local valid, error_msg = utils.validate_provider(provider_config)
        if valid then
            M.register_provider(provider_config)
            utils.log("info", "加载自定义Provider: " .. name)
        else
            utils.log("warn", "无效的自定义Provider: " .. error_msg)
        end
    end
end

-- 注册Provider
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
function M.get_provider(provider_name)
    return M.providers[provider_name]
end

-- 获取当前Provider
function M.get_current_provider()
    local current_name = M.config.provider
    return M.providers[current_name]
end

-- 设置当前Provider
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
    
    -- 添加工具/函数调用支持
    if options.tools and provider.supports_functions then
        local base = require("doodle.providers.base")
        options.functions = base.convert_tools_to_functions(options.tools)
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
function M.list_providers()
    local provider_list = {}
    for name, provider in pairs(M.providers) do
        local info
        if type(provider.get_info) == "function" then
            info = provider:get_info()
        else
            info = {
                name = name,
                description = provider.description,
                model = provider.model,
                stream = provider.stream,
                supports_functions = provider.supports_functions
            }
        end
        table.insert(provider_list, info)
    end
    return provider_list
end

-- 检查Provider是否存在
function M.has_provider(provider_name)
    return M.providers[provider_name] ~= nil
end

-- 统计Provider数量
function M.count_providers()
    local count = 0
    for _ in pairs(M.providers) do
        count = count + 1
    end
    return count
end

-- 获取Provider状态
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
            supports_functions = provider.supports_functions
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
        { role = "user", content = "Hello" }
    }
    
    local test_options = {
        max_tokens = 10,
        stream = false
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
    vim.wait(5000, function() return success or error_msg end)
    
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
        exported_at = utils.get_timestamp()
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