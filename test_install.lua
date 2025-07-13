-- test_install.lua
-- 简单的插件安装测试

print("🎨 测试 Doodle.nvim 插件安装")
print("=" .. string.rep("=", 50))

-- 检查 Neovim 版本
local nvim_version = vim.version()
print("✓ Neovim 版本: " .. nvim_version.major .. "." .. nvim_version.minor .. "." .. nvim_version.patch)

-- 检查依赖
local function check_dependency(name)
    local ok, _ = pcall(require, name)
    if ok then
        print("✓ " .. name .. " 已安装")
        return true
    else
        print("✗ " .. name .. " 未安装")
        return false
    end
end

print("\n📦 检查依赖:")
local plenary_ok = check_dependency("plenary")
local nui_ok = check_dependency("nui")

if not plenary_ok then
    print("⚠️  请安装 plenary.nvim")
end

if not nui_ok then
    print("⚠️  请安装 nui.nvim")
end

-- 检查 Doodle 模块
print("\n🔧 检查 Doodle 模块:")
local function check_doodle_module(name)
    local ok, module = pcall(require, "doodle." .. name)
    if ok then
        print("✓ doodle." .. name .. " 模块加载成功")
        return true, module
    else
        print("✗ doodle." .. name .. " 模块加载失败: " .. tostring(module))
        return false, nil
    end
end

local modules = {
    "utils",
    "prompt", 
    "task",
    "context",
    "tool",
    "provider",
    "agent",
    "ui"
}

local all_modules_ok = true
for _, mod in ipairs(modules) do
    local ok, _ = check_doodle_module(mod)
    if not ok then
        all_modules_ok = false
    end
end

-- 测试基本配置
print("\n⚙️  测试基本配置:")
local config_ok, doodle = pcall(require, "doodle")
if config_ok then
    print("✓ doodle 主模块加载成功")
    
    -- 测试 setup 函数
    local setup_ok, setup_err = pcall(doodle.setup, {
        debug = true,
        log_level = "info",
        provider = "openai",
        custom_tools = {},
        custom_providers = {},
        custom_prompts = {}
    })
    
    if setup_ok then
        print("✓ setup 函数执行成功")
        
        -- 检查配置
        local config = doodle.get_config()
        print("✓ 配置获取成功")
        print("  - Provider: " .. config.provider)
        print("  - 调试模式: " .. tostring(config.debug))
    else
        print("✗ setup 函数执行失败: " .. tostring(setup_err))
        all_modules_ok = false
    end
else
    print("✗ doodle 主模块加载失败: " .. tostring(doodle))
    all_modules_ok = false
end

-- 测试命令
print("\n📝 测试命令:")
local commands = {
    "Doodle",
    "DoodleOpen",
    "DoodleClose",
    "DoodleHelp",
    "DoodleStatus"
}

for _, cmd in ipairs(commands) do
    local cmd_exists = vim.fn.exists(":" .. cmd) == 2
    if cmd_exists then
        print("✓ :" .. cmd .. " 命令可用")
    else
        print("✗ :" .. cmd .. " 命令不可用")
        all_modules_ok = false
    end
end

-- 最终结果
print("\n" .. string.rep("=", 50))
if all_modules_ok and plenary_ok and nui_ok then
    print("🎉 所有测试通过！Doodle.nvim 安装成功！")
    print("\n🚀 使用方法:")
    print("  1. 设置 API Key: export OPENAI_API_KEY='your-key'")
    print("  2. 运行 :Doodle 打开界面")
    print("  3. 输入编程任务并按 Enter")
    print("  4. 运行 :DoodleHelp 查看帮助")
else
    print("❌ 测试失败！请检查安装和配置")
end
print("=" .. string.rep("=", 50)) 