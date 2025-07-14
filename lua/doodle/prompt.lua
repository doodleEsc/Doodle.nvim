-- lua/doodle/prompt.lua
local utils = require("doodle.utils")
local M = {}

-- 内置提示模板
M.builtin_prompts = {
    -- 系统提示
    system = {
        name = "system",
        description = "系统提示，定义Agent的角色和行为",
        template = [[
You are Doodle, a super-intelligent AI agent integrated into Neovim.
Your goal is to be an excellent software development assistant.
- You are professional, precise, and helpful.
- When generating code, prioritize correctness, readability, and best practices.
- You can use a set of predefined tools to interact with the user's environment.
- Current date is: {{current_date}}
        ]],
        variables = {"current_date"}
    },
    think_task = {
        name = "think_task",
        description = "用于分析和规划用户任务的提示",
        template = [[
用户请求：{{user_query}}
请分析这个请求并将其分解为具体的任务步骤。
        ]],
        variables = {"user_query"}
    }
}

-- 初始化模块并加载配置
function M.load(config)
    M.config = config
    
    -- 合并内置提示和自定义提示
    M.config.prompts = vim.tbl_deep_extend("force", 
        utils.deep_copy(M.builtin_prompts), 
        M.config.custom_prompts or {}
    )
    
    utils.log("info", "Prompt模块加载完成，已加载 " .. vim.tbl_count(M.config.prompts) .. " 个提示。")
end

-- 验证提示结构
function M.validate_prompt(prompt)
    return type(prompt) == "table" and type(prompt.name) == "string" and type(prompt.template) == "string"
end

-- 渲染提示模板
function M.render(prompt_name, variables)
    variables = variables or {}
    
    local prompt = M.config.prompts[prompt_name]
    if not prompt then
        utils.log("error", "未找到提示: " .. prompt_name)
        return nil
    end
    
    local template = prompt.template
    local rendered = template
    
    -- 替换变量
    for _, var_name in ipairs(prompt.variables or {}) do
        local value = variables[var_name]
        if value ~= nil then
             rendered = string.gsub(rendered, "{{" .. var_name .. "}}", tostring(value))
        end
    end
    
    return rendered
end

-- 获取上下文变量
function M.get_context_variables()
    return {
        current_date = os.date("%Y-%m-%d"),
    }
end

-- 创建系统消息
function M.create_system_message()
    local vars = M.get_context_variables()
    local content = M.render("system", vars)
    return {
        role = "system",
        content = content
    }
end

-- 准备发送给LLM的最终提示
function M.prepare_prompt(prompt_text, history)
    return prompt_text
end

return M