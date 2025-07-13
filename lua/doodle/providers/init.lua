-- lua/doodle/providers/init.lua
local utils = require("doodle.utils")

local M = {}

-- 加载内置Provider
local openai = require("doodle.providers.openai")
local anthropic = require("doodle.providers.anthropic")
local local_provider = require("doodle.providers.local")
local gemini = require("doodle.providers.gemini")

-- 内置Provider工厂
M.builtin_providers = {
    openai = openai,
    anthropic = anthropic,
    ["local"] = local_provider,
    gemini = gemini
}

-- 创建内置Provider实例
function M.create_builtin_provider(name, config)
    local provider_module = M.builtin_providers[name]
    if not provider_module then
        return nil, "未知的内置Provider: " .. name
    end
    
    local provider = provider_module.create(config)
    local valid, error_msg = provider:validate()
    if not valid then
        return nil, error_msg
    end
    
    return provider, nil
end

-- 获取所有内置Provider信息
function M.get_builtin_providers_info()
    local providers_info = {}
    
    for name, provider_module in pairs(M.builtin_providers) do
        local provider = provider_module.create({})
        providers_info[name] = provider:get_info()
    end
    
    return providers_info
end

-- 检查内置Provider是否存在
function M.has_builtin_provider(name)
    return M.builtin_providers[name] ~= nil
end

-- 列出所有内置Provider名称
function M.list_builtin_providers()
    local names = {}
    for name, _ in pairs(M.builtin_providers) do
        table.insert(names, name)
    end
    return names
end

-- 获取内置Provider数量
function M.count_builtin_providers()
    local count = 0
    for _ in pairs(M.builtin_providers) do
        count = count + 1
    end
    return count
end

-- 注册新的内置Provider
function M.register_builtin_provider(name, provider_module)
    if M.builtin_providers[name] then
        utils.log("warn", "覆盖现有的内置Provider: " .. name)
    end
    
    M.builtin_providers[name] = provider_module
    utils.log("info", "注册内置Provider: " .. name)
end

-- 注销内置Provider
function M.unregister_builtin_provider(name)
    if not M.builtin_providers[name] then
        return false, "内置Provider不存在: " .. name
    end
    
    M.builtin_providers[name] = nil
    utils.log("info", "注销内置Provider: " .. name)
    return true
end

return M 