-- lua/doodle/init.lua
local M = {}

-- 默认配置
M.config = {
    -- API 配置
    api_key = os.getenv("OPENAI_API_KEY"),
    provider = "openai", -- 默认 provider
    
    -- 存储合并后的配置
    providers = {}, -- 用于存储合并后的 providers
    tools = {}, -- 用于存储合并后的 tools
    prompts = {}, -- 用于存储合并后的 prompts
    
    -- 用户自定义配置
    custom_providers = {},
    custom_tools = {},
    custom_prompts = {},
    
    -- UI 配置
    ui = {
        width = 60,
        height = 0.8,
        border = "rounded",
        title = "Doodle.nvim",
    },
    
    -- 任务配置
    task = {
        max_todos = 10,
        timeout = 30000, -- 30秒超时
    },
    
    -- 其他配置
    debug = false,
    log_level = "info",
}

-- 深度合并配置
local function deep_merge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" and type(target[k]) == "table" then
            deep_merge(target[k], v)
        else
            target[k] = v
        end
    end
    return target
end

-- 设置函数
function M.setup(opts)
    opts = opts or {}
    
    -- 深层合并用户配置
    M.config = deep_merge(M.config, opts)
    
    -- 初始化基础模块
    require("doodle.utils").init(M.config)
    
    -- 加载并合并各种组件
    require("doodle.provider").load(M.config)
    require("doodle.tool").load(M.config)
    require("doodle.prompt").load(M.config)
    
    -- 初始化其他模块
    require("doodle.task").load(M.config)
    require("doodle.context").load(M.config)
    require("doodle.agent").init(M.config)
    require("doodle.ui").init(M.config)
    
    if M.config.debug then
        print("Doodle.nvim 初始化完成")
    end
end

-- 获取配置
function M.get_config()
    return M.config
end

return M 