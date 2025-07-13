-- examples/lazy_config.lua
-- Doodle.nvim 配置示例 (使用 lazy.nvim)

return {
    "your-username/Doodle.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim"
    },
    
    -- 懒加载配置
    cmd = {
        "Doodle",
        "DoodleOpen", 
        "DoodleClose",
        "DoodleHelp"
    },
    
    keys = {
        { "<leader>dd", "<cmd>Doodle<cr>", desc = "打开/关闭 Doodle" },
        { "<leader>ds", "<cmd>DoodleStop<cr>", desc = "停止 Doodle Agent" },
        { "<leader>dp", "<cmd>DoodlePause<cr>", desc = "暂停 Doodle Agent" },
        { "<leader>dr", "<cmd>DoodleResume<cr>", desc = "恢复 Doodle Agent" },
    },
    
    opts = {
        -- 基础配置
        api_key = os.getenv("OPENAI_API_KEY"), -- 从环境变量获取
        provider = "openai", -- 默认使用OpenAI
        
        -- UI配置
        ui = {
            width = 80,        -- 侧边栏宽度
            height = 0.85,     -- 侧边栏高度
            border = "rounded", -- 边框样式: "single", "double", "rounded", "solid"
            title = "🎨 Doodle.nvim",
        },
        
        -- 任务配置
        task = {
            max_todos = 20,     -- 最大todo数量
            timeout = 60000,    -- 任务超时时间(毫秒)
        },
        
        -- 自定义工具
        custom_tools = {
            -- 文件操作工具
            {
                name = "read_file",
                description = "读取指定文件的内容",
                parameters = {
                    type = "object",
                    properties = {
                        file_path = {
                            type = "string",
                            description = "要读取的文件路径"
                        }
                    },
                    required = {"file_path"}
                },
                execute = function(args)
                    local file = io.open(args.file_path, "r")
                    if file then
                        local content = file:read("*all")
                        file:close()
                        return {
                            success = true,
                            message = "文件读取成功",
                            content = content
                        }
                    else
                        return {
                            success = false,
                            error = "无法读取文件: " .. args.file_path
                        }
                    end
                end
            },
            
            -- Git工具
            {
                name = "git_diff",
                description = "获取Git差异",
                parameters = {
                    type = "object",
                    properties = {
                        staged = {
                            type = "boolean",
                            description = "是否查看已暂存的更改"
                        }
                    },
                    required = {}
                },
                execute = function(args)
                    local cmd = args.staged and "git diff --cached" or "git diff"
                    local handle = io.popen(cmd)
                    local result = handle:read("*all")
                    handle:close()
                    
                    return {
                        success = true,
                        message = "Git差异获取成功",
                        diff = result
                    }
                end
            },
            
            -- 搜索工具
            {
                name = "search_in_files",
                description = "在项目文件中搜索文本",
                parameters = {
                    type = "object",
                    properties = {
                        pattern = {
                            type = "string",
                            description = "搜索模式"
                        },
                        file_type = {
                            type = "string",
                            description = "文件类型过滤 (如: *.lua, *.py)"
                        }
                    },
                    required = {"pattern"}
                },
                execute = function(args)
                    local cmd = "grep -rn '" .. args.pattern .. "'"
                    if args.file_type then
                        cmd = cmd .. " --include='" .. args.file_type .. "'"
                    end
                    cmd = cmd .. " ."
                    
                    local handle = io.popen(cmd)
                    local result = handle:read("*all")
                    handle:close()
                    
                    return {
                        success = true,
                        message = "搜索完成",
                        results = result
                    }
                end
            }
        },
        
        -- 自定义Provider
        custom_providers = {
            -- Ollama本地模型
            ollama = {
                name = "ollama",
                description = "Ollama 本地模型",
                base_url = "http://localhost:11434/v1",
                model = "codellama:7b",
                request = function(messages, options, callback)
                    return require("doodle.provider").local_request(messages, options, callback)
                end,
                stream = true,
                supports_functions = true
            },
            
            -- 自定义Claude配置
            claude = {
                name = "claude",
                description = "Claude 3 Sonnet",
                base_url = "https://api.anthropic.com/v1",
                model = "claude-3-sonnet-20240229",
                request = function(messages, options, callback)
                    return require("doodle.provider").anthropic_request(messages, options, callback)
                end,
                stream = true,
                supports_functions = true
            }
        },
        
        -- 自定义Prompt
        custom_prompts = {
            -- 代码审查专用
            detailed_code_review = {
                name = "detailed_code_review",
                description = "详细的代码审查提示",
                template = [[
请对以下{{language}}代码进行详细审查：

```{{language}}
{{code}}
```

请从以下方面进行分析：

1. **代码质量**
   - 代码结构和可读性
   - 命名规范
   - 注释质量

2. **性能分析**
   - 时间复杂度
   - 空间复杂度  
   - 潜在的性能瓶颈

3. **安全性**
   - 输入验证
   - 错误处理
   - 安全漏洞

4. **最佳实践**
   - 设计模式应用
   - 代码重构建议
   - 测试覆盖率

5. **改进建议**
   - 具体的优化方案
   - 重构步骤
   - 替代实现

请提供具体的改进代码示例。
                ]],
                variables = {"language", "code"}
            },
            
            -- 调试专用
            debug_helper = {
                name = "debug_helper",
                description = "调试帮助提示",
                template = [[
我遇到了以下问题：

**问题描述：** {{problem_description}}

**相关代码：**
```{{language}}
{{code}}
```

**错误信息：** {{error_message}}

**期望结果：** {{expected_result}}

**当前环境：** {{environment}}

请帮我：
1. 分析问题的根本原因
2. 提供具体的调试步骤
3. 给出修复方案
4. 预防类似问题的建议
                ]],
                variables = {"problem_description", "code", "language", "error_message", "expected_result", "environment"}
            }
        },
        
        -- 高级配置
        debug = false,          -- 调试模式
        log_level = "info",     -- 日志级别: "debug", "info", "warn", "error"
        
        -- API配置
        openai_api_key = os.getenv("OPENAI_API_KEY"),
        anthropic_api_key = os.getenv("ANTHROPIC_API_KEY"),
    },
    
    -- 插件配置完成后的回调
    config = function(_, opts)
        -- 执行setup
        require("doodle").setup(opts)
        
        -- 自定义快捷键
        vim.keymap.set("n", "<leader>dc", function()
            require("doodle.ui").clear_output()
        end, { desc = "清空 Doodle 输出" })
        
        vim.keymap.set("n", "<leader>dh", "<cmd>DoodleHelp<cr>", { desc = "显示 Doodle 帮助" })
        
        -- 自定义命令
        vim.api.nvim_create_user_command("DoodleQuickStart", function()
            require("doodle.ui").open()
            -- 等待UI加载完成后显示快速开始消息
            vim.defer_fn(function()
                require("doodle.ui").display("🚀 快速开始：输入您的编程任务，例如：")
                require("doodle.ui").display("  • '创建一个Python函数来处理JSON数据'")
                require("doodle.ui").display("  • '优化这段代码的性能'")
                require("doodle.ui").display("  • '添加单元测试'")
            end, 500)
        end, { desc = "Doodle 快速开始" })
        
        -- 启动时提示
        if opts.debug then
            vim.notify("Doodle.nvim 已加载完成！使用 :Doodle 开始", vim.log.levels.INFO)
        end
    end
} 