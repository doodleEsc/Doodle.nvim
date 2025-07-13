# Doodle.nvim

一个功能强大的 Neovim 代码助手插件，提供智能的编程任务处理能力。

## ✨ 特性

- 🤖 **智能 Agent 系统**: 自动分析和执行编程任务
- 🎨 **直观的 UI 界面**: 类似 Cursor 的侧边栏交互体验
- 🔧 **丰富的工具系统**: 内置和自定义工具支持
- 🌐 **多 Provider 支持**: OpenAI、Anthropic、本地模型等
- 💬 **流式响应**: 实时显示 AI 处理过程
- 📝 **模板化 Prompt**: 灵活的提示词管理
- 🔄 **任务管理**: 自动分解和跟踪任务进度
- ⚙️ **高度可配置**: 支持自定义工具、Provider 和 Prompt

## 📦 安装

### 依赖要求

- Neovim 0.8+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)

### 使用 lazy.nvim

```lua
{
    "your-username/Doodle.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim"
    },
    opts = {
        -- 基本配置
        api_key = os.getenv("OPENAI_API_KEY"),
        provider = "openai",
        
        -- UI 配置
        ui = {
            width = 60,
            height = 0.8,
            border = "rounded",
            title = "Doodle.nvim",
        },
        
        -- 自定义工具
        custom_tools = {
            {
                name = "my_file_reader",
                description = "读取文件内容",
                parameters = {
                    type = "object",
                    properties = {
                        file_path = {
                            type = "string",
                            description = "文件路径"
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
                            error = "文件读取失败"
                        }
                    end
                end
            }
        },
        
        -- 自定义 Provider
        custom_providers = {
            my_local_model = {
                name = "my_local_model",
                description = "我的本地模型",
                base_url = "http://localhost:11434/v1",
                model = "llama2",
                request = function(messages, options, callback)
                    -- 自定义请求实现
                    return require("doodle.provider").local_request(messages, options, callback)
                end,
                stream = true,
                supports_functions = true
            }
        },
        
        -- 自定义 Prompt
        custom_prompts = {
            code_review = {
                name = "code_review",
                description = "代码审查提示",
                template = [[
请审查以下代码：

```{{language}}
{{code}}
```

请关注：
1. 代码质量和结构
2. 潜在的性能问题
3. 安全性考虑
4. 最佳实践建议
                ]],
                variables = {"language", "code"}
            }
        },
        
        -- 调试模式
        debug = false,
        log_level = "info"
    }
}
```

### 使用 packer.nvim

```lua
use {
    "your-username/Doodle.nvim",
    requires = {
        "nvim-lua/plenary.nvim",
        "MunifTanjim/nui.nvim"
    },
    config = function()
        require("doodle").setup({
            api_key = os.getenv("OPENAI_API_KEY"),
            provider = "openai",
            -- 其他配置...
        })
    end
}
```

## 🚀 快速开始

### 1. 设置 API Key

```bash
# 设置 OpenAI API Key
export OPENAI_API_KEY="your-api-key-here"

# 或者设置 Anthropic API Key
export ANTHROPIC_API_KEY="your-anthropic-key-here"
```

### 2. 打开 Doodle

```vim
:Doodle
```

或使用快捷键：`<leader>dd`

### 3. 开始使用

在输入框中输入你的编程任务，例如：

- "创建一个 Python 函数来处理 CSV 文件"
- "帮我重构这个函数使其更高效"
- "添加错误处理到现有代码"
- "解释这段代码的工作原理"

按 `<Enter>` 提交任务，Agent 会自动分析并执行。

## 🔧 配置选项

### 基本配置

```lua
{
    -- API 配置
    api_key = os.getenv("OPENAI_API_KEY"),
    provider = "openai", -- 默认 provider
    
    -- UI 配置
    ui = {
        width = 60,        -- 侧边栏宽度
        height = 0.8,      -- 侧边栏高度（相对于屏幕）
        border = "rounded", -- 边框样式
        title = "Doodle.nvim",
    },
    
    -- 任务配置
    task = {
        max_todos = 10,    -- 最大 todo 数量
        timeout = 30000,   -- 超时时间（毫秒）
    },
    
    -- 调试配置
    debug = false,         -- 是否启用调试模式
    log_level = "info",    -- 日志级别
}
```

### 自定义工具

```lua
custom_tools = {
    {
        name = "git_status",
        description = "获取 Git 状态",
        parameters = {
            type = "object",
            properties = {},
            required = {}
        },
        execute = function(args)
            local handle = io.popen("git status --porcelain")
            local result = handle:read("*all")
            handle:close()
            
            return {
                success = true,
                message = "Git 状态获取成功",
                status = result
            }
        end
    }
}
```

### 自定义 Provider

```lua
custom_providers = {
    ollama = {
        name = "ollama",
        description = "Ollama 本地模型",
        base_url = "http://localhost:11434/v1",
        model = "llama2",
        request = function(messages, options, callback)
            -- 实现自定义请求逻辑
            return require("doodle.provider").local_request(messages, options, callback)
        end,
        stream = true,
        supports_functions = true
    }
}
```

## 📖 命令

### 主要命令

| 命令 | 描述 |
|------|------|
| `:Doodle` | 打开/关闭侧边栏 |
| `:DoodleOpen` | 打开侧边栏 |
| `:DoodleClose` | 关闭侧边栏 |

### Agent 控制

| 命令 | 描述 |
|------|------|
| `:DoodleStop` | 停止当前 Agent |
| `:DoodlePause` | 暂停当前 Agent |
| `:DoodleResume` | 恢复当前 Agent |
| `:DoodleStatus` | 显示 Agent 状态 |
| `:DoodleProgress` | 显示任务进度 |

### 工具与 Provider

| 命令 | 描述 |
|------|------|
| `:DoodleTools` | 列出所有工具 |
| `:DoodleProviders` | 列出所有 Provider |
| `:DoodleSetProvider <name>` | 切换 Provider |

### 系统命令

| 命令 | 描述 |
|------|------|
| `:DoodleReload` | 重新加载配置 |
| `:DoodleCleanup` | 清理资源 |
| `:DoodleHelp` | 显示帮助信息 |

## ⌨️ 快捷键

### 全局快捷键

| 快捷键 | 描述 |
|--------|------|
| `<leader>dd` | 打开/关闭 Doodle |
| `<leader>ds` | 停止 Agent |
| `<leader>dp` | 暂停 Agent |
| `<leader>dr` | 恢复 Agent |

### 输入框快捷键

| 快捷键 | 描述 |
|--------|------|
| `<Enter>` | 提交查询 |
| `<Ctrl-C>` | 取消任务 |
| `<Ctrl-D>` | 关闭界面 |
| `<Ctrl-L>` | 清空输出 |
| `<Ctrl-P>` | 暂停/恢复 |
| `q` (普通模式) | 关闭界面 |

## 🛠️ 内置工具

### think_task
分析用户请求并将其分解为具体的任务和 todo 项。

### update_task
更新任务中 todo 项的状态。

### finish_task
标记任务完成并退出执行循环。

## 🌐 支持的 Provider

### OpenAI
- 模型：GPT-3.5-turbo, GPT-4 等
- 支持流式响应
- 支持函数调用

### Anthropic (Claude)
- 模型：Claude-3-sonnet 等
- 支持流式响应
- 支持函数调用

### 本地模型
- 兼容 OpenAI API 的本地模型
- 如 Ollama、LocalAI 等

## 🔄 Agent 工作流

1. **接收用户输入**：用户在输入框中提交任务
2. **任务分析**：使用 `think_task` 工具分析并规划任务
3. **任务分解**：将任务分解为多个可执行的 todo 项
4. **循环执行**：逐个执行 todo 项
5. **状态更新**：使用 `update_task` 工具更新执行状态
6. **任务完成**：使用 `finish_task` 工具标记任务完成

## 🎨 使用示例

### 代码生成

```
请帮我创建一个 Python 函数来读取 CSV 文件并返回数据框
```

### 代码审查

```
请审查以下代码的性能和安全性问题
```

### 调试帮助

```
这个函数有什么问题？如何修复？
```

### 重构建议

```
如何重构这段代码使其更符合 SOLID 原则？
```

## 🤝 贡献

欢迎提交 Issues 和 Pull Requests！

### 开发环境设置

1. Clone 仓库
2. 安装依赖
3. 在 Neovim 中测试

### 测试

```bash
# 运行测试
make test

# 格式化代码
make format
```

## 📄 许可证

MIT License

## 🙏 致谢

- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) - 提供基础库支持
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) - 提供 UI 组件支持
- [OpenAI](https://openai.com/) - 提供 AI 模型支持
- [Anthropic](https://anthropic.com/) - 提供 Claude 模型支持

## 📞 支持

如果您在使用过程中遇到问题，请：

1. 查看文档和 FAQ
2. 搜索现有的 Issues
3. 提交新的 Issue
4. 加入讨论群组

---

**享受编程的乐趣！🎉** 