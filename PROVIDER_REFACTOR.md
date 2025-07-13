# Provider 模块重构说明

## 重构概述

本次重构将 `provider.lua` 文件进行了模块化拆分，将抽象框架和具体实现分离，提高了代码的可维护性和可扩展性。

## 重构内容

### 1. 创建 providers 模块目录

```
lua/doodle/providers/
├── init.lua        # providers 模块入口
├── base.lua        # 基础 Provider 类和通用方法
├── openai.lua      # OpenAI Provider 实现
├── anthropic.lua   # Anthropic Provider 实现
└── local.lua       # 本地模型 Provider 实现
```

### 2. Provider 接口规范

每个 Provider 都需要实现以下属性和方法：

- `name`: provider 名称
- `description`: provider 描述
- `base_url`: API 基础 URL
- `model`: 默认模型
- `request`: 请求方法（核心接口）
- `stream`: 是否支持流式响应
- `supports_functions`: 是否支持函数调用
- `handle_stream_request`: 流式请求处理方法
- `handle_sync_request`: 同步请求处理方法

### 3. 为什么不同Provider需要不同的响应处理方法

**重要发现：不同AI提供商的流式和非流式响应格式是不同的！**

#### OpenAI 流式响应格式
```
data: {"choices":[{"delta":{"content":"Hello"}}],"model":"gpt-3.5-turbo"}
data: {"choices":[{"delta":{"content":" World"}}],"model":"gpt-3.5-turbo"}
data: [DONE]
```

#### Anthropic 流式响应格式
```
event: completion
data: {"type": "completion", "completion": "Hello", "stop_reason": null, "model": "claude-2.0"}

event: completion  
data: {"type": "completion", "completion": " World", "stop_reason": null, "model": "claude-2.0"}

event: completion
data: {"type": "completion", "completion": "", "stop_reason": "stop_sequence", "model": "claude-2.0"}
```

#### Google Gemini 流式响应格式
```
data: {"candidates":[{"content":{"parts":[{"text":"Hello"}],"role":"model"}}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":1,"totalTokenCount":2}}

data: {"candidates":[{"content":{"parts":[{"text":" World"}],"role":"model"}}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}

data: {"candidates":[{"content":{"parts":[{"text":""}],"role":"model"},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1,"candidatesTokenCount":2,"totalTokenCount":3}}
```
- 使用 SSE 格式但结构与 OpenAI 差异很大
- 内容在 `candidates[0].content.parts[0].text` 中
- 完成标记通过 `finishReason` 字段判断

### 4. 模块职责分离

#### `lua/doodle/providers/base.lua`
- 定义 `BaseProvider` 基础类
- 提供通用的工具转换功能
- 定义 Provider 验证逻辑
- **不再提供通用的响应处理方法**（因为格式不兼容）

#### `lua/doodle/providers/openai.lua`
- OpenAI Provider 具体实现
- 继承 BaseProvider 类
- 实现 OpenAI 特定的流式/同步响应处理
- 处理 OpenAI 的 SSE 格式和 [DONE] 结束标记

#### `lua/doodle/providers/anthropic.lua`
- Anthropic Provider 具体实现
- 继承 BaseProvider 类
- 实现 Anthropic 特定的流式/同步响应处理
- 处理 Anthropic 的命名事件格式和 ping 事件
- 包含消息格式转换功能

#### `lua/doodle/providers/gemini.lua`
- Google Gemini Provider 具体实现
- 继承 BaseProvider 类
- 实现 Gemini 特定的流式/同步响应处理
- 处理 Gemini 的候选响应格式和 finishReason 结束标记
- 包含消息格式转换功能（assistant → model）
- 支持 Gemini 特有的安全设置和生成配置

#### `lua/doodle/providers/local.lua`
- 本地模型 Provider 具体实现
- 继承 BaseProvider 类
- 实现本地模型 API 请求逻辑
- 通常使用 OpenAI 兼容格式

#### `lua/doodle/providers/init.lua`
- providers 模块入口
- 管理内置 Provider 工厂
- 提供 Provider 创建和管理功能

#### `lua/doodle/provider.lua`（重构后）
- 保留抽象框架的通用代码
- Provider 注册表管理
- 请求分发逻辑
- Provider 生命周期管理

### 5. 主要改进

1. **模块化设计**：将不同 Provider 的具体实现分离到独立文件
2. **接口规范化**：定义清晰的 Provider 接口规范
3. **响应格式特化**：每个 Provider 处理自己的响应格式
4. **可扩展性**：新增 Provider 只需实现接口即可
5. **维护性**：每个 Provider 独立维护，降低耦合度

### 6. 响应处理方法的实现

#### OpenAI 处理方法
```lua
-- 处理OpenAI的Server-Sent Events格式
function M.OpenAIProvider:handle_stream_request(curl, url, data, headers, callback)
    -- 寻找 "data: " 前缀
    -- 解析 choices[0].delta.content
    -- 处理 "[DONE]" 结束标记
end
```

#### Anthropic 处理方法
```lua
-- 处理Anthropic的Server-Sent Events格式
function M.AnthropicProvider:handle_stream_request(curl, url, data, headers, callback)
    -- 寻找 "event: " 前缀
    -- 解析 completion 字段
    -- 处理 ping 和 error 事件
end
```

#### Gemini 处理方法
```lua
-- 处理Gemini的Server-Sent Events格式
function M.GeminiProvider:handle_stream_request(curl, url, data, headers, callback)
    -- 解析 candidates[0].content.parts[0].text
    -- 处理 finishReason 结束标记
    -- 支持 Gemini 特有的安全设置
end
```

#### 本地模型处理方法
```lua
-- 处理OpenAI兼容的Server-Sent Events格式
function M.LocalProvider:handle_stream_request(curl, url, data, headers, callback)
    -- 大多数本地模型使用OpenAI兼容格式
end
```

### 7. 使用方式

#### 创建内置 Provider

```lua
local providers = require("doodle.providers")

-- 创建 OpenAI Provider
local openai_provider, err = providers.create_builtin_provider("openai", {
    api_key = "your-api-key"
})

-- 创建 Anthropic Provider
local anthropic_provider, err = providers.create_builtin_provider("anthropic", {
    api_key = "your-api-key"
})

-- 创建 Gemini Provider
local gemini_provider, err = providers.create_builtin_provider("gemini", {
    api_key = "your-api-key",
    model = "gemini-pro"
})
```

#### 自定义 Provider

```lua
local base = require("doodle.providers.base")

-- 创建自定义 Provider
local MyProvider = {}
MyProvider.__index = MyProvider
setmetatable(MyProvider, { __index = base.BaseProvider })

function MyProvider:new(config)
    config.name = "my-provider"
    config.description = "我的自定义Provider"
    -- ... 其他配置
    
    local instance = base.BaseProvider:new(config)
    setmetatable(instance, self)
    return instance
end

function MyProvider:request(messages, options, callback)
    -- 实现请求逻辑
end

-- 必须实现自己的响应处理方法
function MyProvider:handle_stream_request(curl, url, data, headers, callback)
    -- 实现流式响应处理
end

function MyProvider:handle_sync_request(curl, url, data, headers, callback)
    -- 实现同步响应处理
end
```

### 8. 向后兼容性

重构后的代码保持与原 API 的兼容性，现有的调用方式不需要修改。

## 测试验证

重构完成后已通过完整的功能测试，包括：

- ✅ 模块加载测试
- ✅ 内置 Provider 信息获取
- ✅ Provider 实例创建
- ✅ Provider 验证
- ✅ 工具转换功能
- ✅ 响应格式特化处理

## 总结

本次重构成功实现了 Provider 模块的模块化拆分，**最重要的改进是发现并解决了不同AI提供商响应格式不兼容的问题**。通过让每个 Provider 实现自己的响应处理方法，我们提高了代码的可维护性和可扩展性，同时保持了良好的向后兼容性。 