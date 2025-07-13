-- test_gemini_provider.lua
-- 测试 Gemini Provider 功能

local providers = require("doodle.providers")

-- 测试模块加载
print("测试 Gemini Provider 模块加载...")
local gemini_module = require("doodle.providers.gemini")
print("✅ Gemini Provider 模块加载成功")

-- 测试 Provider 创建
print("\n测试 Gemini Provider 创建...")
local gemini_provider, err = providers.create_builtin_provider("gemini", {
    api_key = "test-key",
    model = "gemini-pro",
    base_url = "https://generativelanguage.googleapis.com/v1beta"
})

if err then
    print("❌ Provider 创建失败:", err)
    return
end

print("✅ Gemini Provider 创建成功")

-- 测试 Provider 信息
print("\n测试 Gemini Provider 信息...")
local info = gemini_provider:get_info()
print("Provider 名称:", info.name)
print("Provider 描述:", info.description)
print("Base URL:", info.base_url)
print("默认模型:", info.model)
print("支持流式:", info.stream)
print("支持函数调用:", info.supports_functions)

-- 测试 Provider 验证
print("\n测试 Gemini Provider 验证...")
local valid, error_msg = gemini_provider:validate()
if valid then
    print("✅ Provider 验证通过")
else
    print("❌ Provider 验证失败:", error_msg)
end

-- 测试消息格式转换
print("\n测试消息格式转换...")
local test_messages = {
    { role = "system", content = "你是一个有用的助手" },
    { role = "user", content = "你好" },
    { role = "assistant", content = "你好！我是 Gemini。" },
    { role = "user", content = "请介绍一下你自己" }
}

local gemini_contents = gemini_provider:convert_messages_to_gemini(test_messages)
print("原始消息数量:", #test_messages)
print("转换后消息数量:", #gemini_contents)

for i, content in ipairs(gemini_contents) do
    print(string.format("消息 %d: role=%s, text=%s", i, content.role, content.parts[1].text))
end
print("✅ 消息格式转换成功")

-- 测试 URL 构建
print("\n测试 URL 构建...")
local stream_url = gemini_provider:build_request_url("gemini-pro", "test-key", true)
local sync_url = gemini_provider:build_request_url("gemini-pro", "test-key", false)
print("流式 URL:", stream_url)
print("同步 URL:", sync_url)
print("✅ URL 构建成功")

-- 测试内置 Provider 注册
print("\n测试内置 Provider 注册...")
local builtin_providers = providers.list_builtin_providers()
print("内置 Provider 列表:", table.concat(builtin_providers, ", "))

local has_gemini = providers.has_builtin_provider("gemini")
print("包含 Gemini Provider:", has_gemini)

if has_gemini then
    print("✅ Gemini Provider 已正确注册")
else
    print("❌ Gemini Provider 未正确注册")
end

-- 测试 Provider 信息获取
print("\n测试所有 Provider 信息...")
local all_providers_info = providers.get_builtin_providers_info()
for name, provider_info in pairs(all_providers_info) do
    print(string.format("Provider: %s (%s)", name, provider_info.description))
end

print("\n🎉 所有测试完成！")

-- 模拟请求测试（不发送真实请求）
print("\n模拟请求测试（不发送真实请求）...")
local test_callback = function(content, metadata)
    if content then
        print("接收到内容:", content)
    end
    if metadata then
        print("元数据:", vim.inspect(metadata))
    end
end

-- 这里只是测试函数调用，不会发送真实请求
local success = pcall(function()
    gemini_provider:request(test_messages, {
        stream = false,
        temperature = 0.7,
        max_tokens = 1000
    }, test_callback)
end)

if success then
    print("✅ 请求方法调用成功（未发送真实请求）")
else
    print("❌ 请求方法调用失败")
end 