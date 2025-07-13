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
你是一个专业的编程助手，专门帮助开发者完成各种编程任务。

你的职责：
1. 理解用户的编程需求
2. 将复杂任务分解为可执行的步骤
3. 提供准确的代码解决方案
4. 使用提供的工具完成任务

你的工作流程：
1. 使用 think_task 工具分析并规划用户的请求
2. 逐步执行每个任务步骤
3. 使用 update_task 工具更新任务状态
4. 完成后使用 finish_task 工具结束任务

注意事项：
- 请始终使用中文回复
- 确保代码质量和最佳实践
- 提供清晰的解释和注释
- 及时更新任务状态
        ]],
        variables = {}
    },
    
    -- 思考任务提示
    think_task = {
        name = "think_task",
        description = "用于分析和规划用户任务的提示",
        template = [[
用户请求：{{user_query}}

请分析这个请求并将其分解为具体的任务步骤。

分析要求：
1. 理解用户的真实需求
2. 识别需要完成的具体任务
3. 将任务分解为可执行的步骤（todos）
4. 为每个步骤提供清晰的描述

当前上下文：
- 当前文件：{{current_file}}
- 当前目录：{{current_dir}}
- 选中文本：{{selected_text}}

请思考并规划这个任务。
        ]],
        variables = {
            "user_query",
            "current_file", 
            "current_dir",
            "selected_text"
        }
    },
    
    -- 代码生成提示
    code_generation = {
        name = "code_generation",
        description = "用于生成代码的提示",
        template = [[
任务：{{task_description}}

要求：
1. 生成高质量的代码
2. 遵循最佳实践和编码规范
3. 添加必要的注释和文档
4. 确保代码的可读性和可维护性

上下文信息：
- 编程语言：{{language}}
- 项目类型：{{project_type}}
- 相关文件：{{related_files}}

请生成相应的代码。
        ]],
        variables = {
            "task_description",
            "language",
            "project_type", 
            "related_files"
        }
    },
    
    -- 代码审查提示
    code_review = {
        name = "code_review",
        description = "用于代码审查的提示",
        template = [[
请审查以下代码：

```{{language}}
{{code}}
```

审查要点：
1. 代码质量和结构
2. 潜在的bug和问题
3. 性能优化建议
4. 代码风格和规范
5. 安全性考虑

请提供详细的审查意见和改进建议。
        ]],
        variables = {
            "code",
            "language"
        }
    },
    
    -- 调试提示
    debug = {
        name = "debug",
        description = "用于调试代码的提示",
        template = [[
调试任务：{{debug_task}}

问题描述：{{problem_description}}

相关代码：
```{{language}}
{{code}}
```

错误信息：{{error_message}}

请分析问题并提供解决方案：
1. 问题的根本原因
2. 具体的修复步骤
3. 预防类似问题的建议
        ]],
        variables = {
            "debug_task",
            "problem_description",
            "code",
            "language",
            "error_message"
        }
    }
}

-- 加载配置
function M.load(config)
    M.config = config
    
    -- 合并内置提示
    config.prompts = utils.deep_copy(M.builtin_prompts)
    
    -- 加载自定义提示
    if config.custom_prompts then
        for name, prompt in pairs(config.custom_prompts) do
            if M.validate_prompt(prompt) then
                config.prompts[name] = prompt
                utils.log("info", "加载自定义提示: " .. name)
            else
                utils.log("warn", "无效的自定义提示: " .. name)
            end
        end
    end
    
    utils.log("info", "Prompt模块加载完成")
end

-- 验证提示结构
function M.validate_prompt(prompt)
    if type(prompt) ~= "table" then
        return false
    end
    
    if utils.is_string_empty(prompt.name) then
        return false
    end
    
    if utils.is_string_empty(prompt.template) then
        return false
    end
    
    if prompt.variables and type(prompt.variables) ~= "table" then
        return false
    end
    
    return true
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
        local value = variables[var_name] or ""
        local pattern = "{{" .. var_name .. "}}"
        rendered = string.gsub(rendered, pattern, tostring(value))
    end
    
    -- 处理剩余的未替换变量（设为空）
    rendered = string.gsub(rendered, "{{[^}]+}}", "")
    
    utils.log("debug", "渲染提示: " .. prompt_name)
    return rendered
end

-- 获取提示信息
function M.get_prompt(name)
    return M.config.prompts[name]
end

-- 列出所有提示
function M.list_prompts()
    local prompts = {}
    for name, prompt in pairs(M.config.prompts) do
        table.insert(prompts, {
            name = name,
            description = prompt.description,
            variables = prompt.variables or {}
        })
    end
    return prompts
end

-- 添加自定义提示
function M.add_prompt(name, prompt)
    if not M.validate_prompt(prompt) then
        utils.log("error", "无效的提示结构: " .. name)
        return false
    end
    
    M.config.prompts[name] = prompt
    utils.log("info", "添加自定义提示: " .. name)
    return true
end

-- 移除提示
function M.remove_prompt(name)
    if M.builtin_prompts[name] then
        utils.log("warn", "不能移除内置提示: " .. name)
        return false
    end
    
    M.config.prompts[name] = nil
    utils.log("info", "移除提示: " .. name)
    return true
end

-- 获取当前上下文变量
function M.get_context_variables()
    local variables = {}
    
    -- 基础上下文
    variables.current_file = utils.get_current_file()
    variables.current_dir = utils.get_current_dir()
    variables.selected_text = utils.get_visual_selection()
    variables.timestamp = utils.get_timestamp()
    
    -- 缓冲区信息
    local bufnr = vim.api.nvim_get_current_buf()
    variables.buffer_content = utils.get_buffer_content(bufnr)
    variables.filetype = vim.bo.filetype
    
    -- 项目信息
    variables.project_type = M.detect_project_type()
    variables.language = M.detect_language()
    
    return variables
end

-- 检测项目类型
function M.detect_project_type()
    local current_dir = utils.get_current_dir()
    local project_files = {
        "package.json", "pom.xml", "Cargo.toml", "go.mod",
        "requirements.txt", "setup.py", "composer.json"
    }
    
    for _, file in ipairs(project_files) do
        local file_path = current_dir .. "/" .. file
        if vim.fn.filereadable(file_path) == 1 then
            return file
        end
    end
    
    return "unknown"
end

-- 检测编程语言
function M.detect_language()
    local filetype = vim.bo.filetype
    if filetype and filetype ~= "" then
        return filetype
    end
    
    local filename = vim.fn.expand("%:t")
    local extensions = {
        [".js"] = "javascript",
        [".ts"] = "typescript",
        [".py"] = "python",
        [".lua"] = "lua",
        [".go"] = "go",
        [".java"] = "java",
        [".cpp"] = "cpp",
        [".c"] = "c",
    }
    
    for ext, lang in pairs(extensions) do
        if string.match(filename, ext .. "$") then
            return lang
        end
    end
    
    return "text"
end

-- 创建系统消息
function M.create_system_message(variables)
    local rendered = M.render("system", variables)
    return utils.format_message("system", rendered)
end

-- 创建用户消息
function M.create_user_message(content, variables)
    variables = variables or {}
    variables.user_query = content
    
    -- 如果是特定的任务类型，使用对应的模板
    local rendered = content
    if variables.prompt_type then
        rendered = M.render(variables.prompt_type, variables)
    end
    
    return utils.format_message("user", rendered)
end

return M 