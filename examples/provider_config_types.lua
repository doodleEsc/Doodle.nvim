-- examples/provider_config_types.lua
-- Provider配置类型定义示例

require("doodle.types")

-- 现在配置custom_providers时会有精确的类型提示
---@type DoodleConfig
local config = {
    default_provider = "openai",
    log_level = "info",
    
    -- 自定义provider配置，所有provider都使用统一的配置结构
    custom_providers = {
        -- OpenAI provider配置 - 统一使用api_key字段
        my_openai = {
            model = "gpt-4",
            base_url = "https://api.openai.com/v1",
            api_key = "sk-xxxxxxxxxxxx",  -- 统一的API key字段
            stream = true,
            supports_functions = true,
            extra_body = {  -- 额外的请求参数
                reasoning = true,  -- 启用推理功能
                response_format = { type = "json_object" }  -- 指定响应格式
            }
        },
        
        -- Anthropic provider配置 - 统一使用api_key字段
        my_claude = {
            model = "claude-3-sonnet-20240229",
            base_url = "https://api.anthropic.com/v1", 
            api_key = "sk-ant-xxxxxxxxxxxx",  -- 统一的API key字段
            stream = true,
            supports_functions = true,
            extra_body = {  -- 额外的请求参数
                metadata = { user_id = "user_123" },  -- 添加元数据
                anthropic_version = "2023-06-01"  -- 指定API版本
            }
        },
        
        -- Gemini provider配置 - 统一使用api_key字段
        my_gemini = {
            model = "gemini-pro",
            base_url = "https://generativelanguage.googleapis.com/v1beta",
            api_key = "AIzaSyXXXXXXXXXXXXXX",  -- 统一的API key字段
            stream = true,
            supports_functions = true
        },
        
        -- Local provider配置 - 统一使用api_key字段（可选）
        my_local = {
            model = "llama2-7b",
            base_url = "http://localhost:8080/v1",
            api_key = "",  -- 统一的API key字段（本地模型通常为空）
            stream = false,
            supports_functions = false
        },
        
        -- 自定义provider配置 - 统一使用api_key字段
        custom_provider = {
            name = "custom_provider",
            model = "custom-model",
            base_url = "https://my-custom-api.com/v1",
            api_key = "custom_api_key_xxxxxxxxxxxx",  -- 统一的API key字段
            stream = true,
            supports_functions = true,
            extra_body = {  -- 额外的请求参数
                custom_param = "custom_value",  -- 自定义参数
                special_mode = true,  -- 特殊模式
                advanced_options = {  -- 嵌套配置
                    optimization_level = 2,
                    cache_enabled = true
                }
            }
        }
    }
}

return config

--[[
统一配置设计说明：

1. DoodleCustomProviderConfig: 
   - 所有自定义provider都使用相同的配置结构
   - 统一字段：name, description, base_url, model, api_key, stream, supports_functions, extra_body
   - 所有provider都使用 api_key 作为密钥字段名
   - extra_body 用于向API请求中添加额外参数（如reasoning, response_format等）

2. Provider实现层面的API key处理：
   - OpenAI Provider: 优先从 config.api_key 获取，回退到环境变量 OPENAI_API_KEY
   - Anthropic Provider: 优先从 config.api_key 获取，回退到环境变量 ANTHROPIC_API_KEY  
   - Gemini Provider: 优先从 config.api_key 获取，回退到环境变量 GEMINI_API_KEY
   - Local Provider: 直接使用 config.api_key（通常为空）

这样的设计优点：
- 配置层面完全统一，简化用户配置
- 类型定义简洁清晰，避免字段混乱
- 每个provider在实现中灵活处理自己的密钥获取逻辑
- extra_body提供灵活的扩展能力，支持各种API特有参数
- 保持向后兼容性
- 遵循配置简单、实现灵活的原则
]] 