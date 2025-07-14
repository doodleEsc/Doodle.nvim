---@meta

---
--- Doodle.nvim 类型定义
--- 提供完整的类型支持和智能提示
---

-- =============================================================================
-- 基础类型定义
-- =============================================================================

---@alias DoodleLogLevel "debug" | "info" | "warn" | "error"

---@class DoodleMessage
---@field role "user" | "assistant" | "system"
---@field content string
---@field timestamp? string

---@class DoodleRequestOptions
---@field model? string
---@field temperature? number
---@field max_tokens? number
---@field stream? boolean
---@field tools? DoodleTool[]
---@field tool_choice? string | table
---@field api_key? string

-- =============================================================================
-- Provider 相关类型
-- =============================================================================

---@class DoodleProviderConfig
---@field name string
---@field description? string
---@field base_url string
---@field model string
---@field api_key? string
---@field stream? boolean
---@field supports_functions? boolean
---@field extra_body? table<string, any>

---@class DoodleProviderInfo
---@field name string
---@field description string
---@field base_url string
---@field model string
---@field api_key string
---@field stream boolean
---@field supports_functions boolean
---@field extra_body table<string, any>

---@class DoodleCustomProviderConfig
---@field name? string
---@field description? string
---@field base_url? string
---@field model? string
---@field api_key? string
---@field stream? boolean
---@field supports_functions? boolean
---@field extra_body? table<string, any>

---@alias DoodleCustomProvidersConfig table<string, DoodleCustomProviderConfig>

---@class DoodleBaseProvider
---@field name string
---@field description string
---@field base_url string
---@field model string
---@field api_key string
---@field stream boolean
---@field supports_functions boolean
---@field extra_body table<string, any>
---@field config table
---@field new fun(self: DoodleBaseProvider, config: DoodleProviderConfig): DoodleBaseProvider
---@field request fun(self: DoodleBaseProvider, messages: DoodleMessage[], options: DoodleRequestOptions, callback: function): boolean
---@field handle_stream_request fun(self: DoodleBaseProvider, curl: any, url: string, data: table, headers: table, callback: function): boolean
---@field handle_sync_request fun(self: DoodleBaseProvider, curl: any, url: string, data: table, headers: table, callback: function): boolean
---@field validate fun(self: DoodleBaseProvider): boolean, string?
---@field get_info fun(self: DoodleBaseProvider): DoodleProviderInfo
---@field get_api_key fun(self: DoodleBaseProvider): string
---@field get_masked_api_key fun(self: DoodleBaseProvider): string

---@class DoodleOpenAIProvider : DoodleBaseProvider
---@field new fun(self: DoodleOpenAIProvider, config: DoodleProviderConfig): DoodleOpenAIProvider

---@class DoodleAnthropicProvider : DoodleBaseProvider
---@field new fun(self: DoodleAnthropicProvider, config: DoodleProviderConfig): DoodleAnthropicProvider
---@field convert_messages_to_anthropic fun(self: DoodleAnthropicProvider, messages: DoodleMessage[]): table[]
---@field convert_tools_to_anthropic fun(self: DoodleAnthropicProvider, tools: DoodleTool[]): table[]

---@class DoodleGeminiProvider : DoodleBaseProvider
---@field new fun(self: DoodleGeminiProvider, config: DoodleProviderConfig): DoodleGeminiProvider
---@field convert_messages_to_gemini fun(self: DoodleGeminiProvider, messages: DoodleMessage[]): table[]
---@field build_request_url fun(self: DoodleGeminiProvider, model: string, api_key: string, stream: boolean): string

---@class DoodleLocalProvider : DoodleBaseProvider
---@field new fun(self: DoodleLocalProvider, config: DoodleProviderConfig): DoodleLocalProvider

-- =============================================================================
-- 工具相关类型
-- =============================================================================

---@class DoodleToolParameter
---@field type string
---@field description string
---@field enum? string[]
---@field items? DoodleToolParameter
---@field properties? table<string, DoodleToolParameter>
---@field required? string[]

---@class DoodleToolFunction
---@field name string
---@field description string
---@field parameters DoodleToolParameter

---@class DoodleTool
---@field type "function"
---@field function DoodleToolFunction

---@class DoodleBaseTool
---@field name string
---@field description string
---@field parameters DoodleToolParameter
---@field execute fun(self: DoodleBaseTool, input: table, context: DoodleAgentContext): any

---@class DoodleThinkTaskTool : DoodleBaseTool
---@field new fun(): DoodleThinkTaskTool

---@class DoodleUpdateTaskTool : DoodleBaseTool
---@field new fun(): DoodleUpdateTaskTool

---@class DoodleFinishTaskTool : DoodleBaseTool
---@field new fun(): DoodleFinishTaskTool

-- =============================================================================
-- Agent 和 Context 相关类型
-- =============================================================================

---@class DoodleAgentContext
---@field provider DoodleBaseProvider
---@field messages DoodleMessage[]
---@field tools DoodleBaseTool[]
---@field task_status? string
---@field task_progress? number
---@field task_description? string

---@class DoodleAgent
---@field provider DoodleBaseProvider
---@field tools DoodleBaseTool[]
---@field context DoodleAgentContext
---@field new fun(provider: DoodleBaseProvider, tools?: DoodleBaseTool[]): DoodleAgent
---@field chat fun(self: DoodleAgent, message: string, options?: DoodleRequestOptions): string?
---@field chat_stream fun(self: DoodleAgent, message: string, callback: function, options?: DoodleRequestOptions): boolean

-- =============================================================================
-- 配置相关类型
-- =============================================================================

---@class DoodleConfig
---@field providers? table<string, DoodleBaseProvider>
---@field custom_providers? DoodleCustomProvidersConfig
---@field default_provider? string
---@field log_level? DoodleLogLevel
---@field api_key? string
---@field openai_api_key? string
---@field anthropic_api_key? string
---@field gemini_api_key? string
---@field local_api_key? string
---@field base_url? string
---@field model? string
---@field stream? boolean
---@field supports_functions? boolean

-- =============================================================================
-- 回调函数类型
-- =============================================================================

---@alias DoodleStreamCallback fun(chunk: string?, meta: table?): nil
---@alias DoodleCompletionCallback fun(response: string?, error: string?): nil

-- =============================================================================
-- 响应类型
-- =============================================================================

---@class DoodleOpenAIChoice
---@field index number
---@field message? DoodleMessage
---@field delta? DoodleMessage
---@field finish_reason? string

---@class DoodleOpenAIResponse
---@field id string
---@field object string
---@field created number
---@field model string
---@field choices DoodleOpenAIChoice[]
---@field usage? table

---@class DoodleAnthropicResponse
---@field id string
---@field type string
---@field role string
---@field content table[]
---@field model string
---@field stop_reason? string
---@field usage? table

---@class DoodleGeminiCandidate
---@field content table
---@field finishReason? string
---@field index number

---@class DoodleGeminiResponse
---@field candidates DoodleGeminiCandidate[]
---@field usageMetadata? table

-- =============================================================================
-- 模块导出类型
-- =============================================================================

---@class DoodleProviderModule
---@field providers table<string, DoodleBaseProvider>
---@field config DoodleConfig
---@field init fun(config: DoodleConfig): nil
---@field load fun(config: DoodleConfig): nil
---@field load_builtin_providers fun(): nil
---@field load_custom_providers fun(custom_providers: DoodleCustomProvidersConfig): nil
---@field register_provider fun(provider: DoodleBaseProvider): nil
---@field get_provider fun(name: string): DoodleBaseProvider?
---@field list_providers fun(): DoodleProviderInfo[]
---@field has_provider fun(name: string): boolean
---@field count_providers fun(): number

---@class DoodleToolModule
---@field tools table<string, DoodleBaseTool>
---@field load_builtin_tools fun(): nil
---@field register_tool fun(tool: DoodleBaseTool): nil
---@field get_tool fun(name: string): DoodleBaseTool?
---@field list_tools fun(): DoodleBaseTool[]
---@field get_tool_definitions fun(): DoodleTool[]

---@class DoodleModule
---@field setup fun(config?: DoodleConfig): nil
---@field create_agent fun(provider_name: string): DoodleAgent?
---@field chat fun(message: string, provider_name?: string): string?
---@field chat_stream fun(message: string, callback: DoodleStreamCallback, provider_name?: string): boolean 