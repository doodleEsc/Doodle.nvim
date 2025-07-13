# Doodle.nvim 开发计划 (修订版)

---

## Thought 1: 项目脚手架与核心配置

**目标:** 搭建新的项目结构，并设计一个强大的 `setup` 函数，使其能够通过配置表来接收自定义工具和 Provider。

**步骤:**

1. **创建目录结构 (已修改):**
    插件的 Lua 模块根目录将修改为 `lua/doodle/`。

    ```
    Doodle.nvim/
    ├── lua/
    │   └── doodle/
    │       ├── init.lua        -- 主入口，负责 setup 和配置管理
    │       ├── agent.lua         -- Agent 核心逻辑 (无 UI 依赖)
    │       ├── context.lua       -- 消息上下文管理
    │       ├── provider.lua      -- Provider 抽象和加载逻辑
    │       ├── task.lua          -- 任务和Todo数据结构及管理
    │       ├── tool.lua          -- Tool 抽象和加载逻辑
    │       ├── ui.lua            -- UI 模块 (nui.nvim)
    │       ├── prompt.lua        -- Prompt 管理
    │       └── utils.lua         -- 辅助函数
    ├── plugin/
    │   └── doodle.lua        -- 插件加载和 UI 命令定义
    └── README.md
    ```

2. **主入口与配置管理 (`init.lua`):**
    `setup` 函数将成为配置的中心，负责合并默认配置、用户配置、内置及自定义的工具和 Provider。

    ```lua
    -- lua/doodle/init.lua
    local M = {}

    -- 默认配置
    M.config = {
        api_key = os.getenv("OPENAI_API_KEY"), -- 示例
        provider = "openai", -- 默认 provider
        providers = {}, -- 用于存储合并后的 providers
        tools = {}, -- 用于存储合并后的 tools
        prompts = {}, -- 用于存储合并后的 prompts
        -- ... 其他配置
    }

    function M.setup(opts)
        -- 深层合并用户配置
        M.config = vim.tbl_deep_extend("force", M.config, opts or {})

        -- 加载并合并 providers, tools, prompts
        require("doodle.provider").load(M.config)
        require("doodle.tool").load(M.config)
        require("doodle.prompt").load(M.config)
    end

    return M
    ```

3. **`lazy.nvim` 配置示例 (已修改):**
    `README.md` 中的示例将展示如何通过 `opts` 传入自定义工具和 Provider。

    ```lua
    -- lazy.nvim anfiguration
    {
        "your-username/Doodle.nvim",
        dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
        opts = {
            provider = "openai", -- 或其他自定义 provider 的名字
            -- 自定义 Provider
            custom_providers = {
                openai = require("my-custom-openai-provider"),
            },
            -- 自定义工具
            custom_tools = {
                {
                    name = "my_file_reader",
                    description = "读取文件内容",
                    execute = function(args)
                        -- ... 实现
                        return "文件内容..."
                    end,
                },
            },
        },
    }
    ```

4. **插件加载文件 (`plugin/doodle.lua`):**
    此文件现在只负责创建 UI 相关的命令，例如 `:Doodle` 来打开或关闭侧边栏。

    ```lua
    -- plugin/doodle.lua
    vim.api.nvim_create_user_command(
        "Doodle",
        function()
            require("doodle.ui").toggle()
        end,
        { nargs = 0 }
    )
    ```

---

## Thought 2: UI 模块的独立开发

**目标:** 创建一个完全解耦的 UI 模块。UI 负责展示信息和捕获用户输入，并将输入内容传递给 Agent 核心。

**步骤:**

1. **UI 模块 (`ui.lua`):**
    * **核心功能:**
        * `toggle()`: 创建、显示或销毁侧边栏的主函数。
        * `mount()`: 使用 `nui.nvim` 构建界面布局（80/20 分割）。
        * `unmount()`: 销毁界面。
        * `display(message)`: 向输出窗口追加消息。此函数应处理代码块、普通文本等不同格式。
    * **输入处理:**
        * 在 `mount` 函数中，为 `nui.Input` 组件绑定一个 `on_submit` 回调。
        * **关键修改:** `on_submit` 回调函数将执行以下操作：
            1. 获取输入框中的文本 (`query`)。
            2. 清空输入框。
            3. 调用 `require("doodle.agent").start(query, { on_output = M.display })` 来启动 Agent。`on_output` 回调将 UI 的 `display` 函数传递给 Agent，以便 Agent 可以将结果打印回 UI。

---

## Thought 3: 工具和 Provider 的加载逻辑

**目标:** 实现从 `M.config` 加载内置和自定义工具/Provider 的逻辑。

**步骤:**

1. **Tool 模块 (`tool.lua`):**
    * `load(config)` 函数:
        1. 加载所有内置工具（`think_task`, `update_task`, `finish_task`）。
        2. 遍历 `config.custom_tools`（一个工具对象的列表），将其与内置工具合并。
        3. 将最终的工具列表存储在 `config.tools` 中，以便 Agent 调用。
    * **`finish_task` 工具 (已修改):**
        * 此工具的 `execute` 函数现在**只**调用 `require("doodle.task").update_status(task_id, "completed")`。它不再与 Agent 直接交互或调用任何 `stop` 方法。

2. **Provider 模块 (`provider.lua`):**
    * `load(config)` 函数:
        1. 加载内置的 Provider（例如 `openai`）。
        2. 遍历 `config.custom_providers`（一个 `name` 到实现的映射表），将其与内置 Provider 合并。
        3. 将最终的 Provider 表存储在 `config.providers` 中。

---

## Thought 4: Agent 核心逻辑与工作流重构

**目标:** 重构 Agent 的核心逻辑，使其独立于 UI，并基于任务状态来控制其生命周期。

**步骤:**

1. **Agent 模块 (`agent.lua`):**
    * **`start(query, callbacks)` 函数:**
        * 此函数是 Agent 的入口点，由 UI 的 `on_submit` 回调触发。
        * `callbacks` 参数是一个表，例如 `{ on_output = function(msg) ... end }`。Agent 将使用 `callbacks.on_output` 来发送消息，而不是直接调用 UI 函数。
        * **流程:**
            1. 保存 `callbacks`。
            2. 调用 `think_task` 工具，传入 `query`，生成一个新任务并获取 `task_id`。
            3. 启动 `agent_loop(task_id)`。
    * **`agent_loop(task_id)` 函数 (已修改):**
        * 这是一个异步循环，其**循环条件**是检查当前任务的状态。
        * **伪代码:**

            ```lua
            function Agent:agent_loop(task_id)
                while not require("doodle.task").is_complete(task_id) do
                    local todo = require("doodle.task").get_next_todo(task_id)
                    if not todo then
                        -- 所有todo已完成，但任务状态可能还未更新，等待finish_task
                        break
                    end

                    -- 1. 准备消息上下文
                    -- 2. 调用 Provider.request
                    -- 3. 流式处理响应，通过 on_output 回调将内容发送到 UI
                    -- 4. 如果检测到工具调用，则执行工具
                    -- 5. 工具执行结果会再次通过 Provider 发送给 LLM
                    -- 6. 当一个 todo 完成后，LLM 会调用 update_task 工具
                    -- (循环会自然地继续到下一个todo或因 is_complete 变为 true 而终止)
                end

                -- 循环结束，任务完成
                self.callbacks.on_output("任务已完成。")
            end
            ```

    * **循环控制 (关键修改):** Agent 的生命周期完全由 `task` 的状态驱动。当 `finish_task` 工具将任务状态更新为 `completed` 后，`agent_loop` 的 `while` 条件在下一次检查时会变为 `false`，循环将自然、优雅地退出。

---

## Thought 5: 任务模块与上下文管理

**目标:** 确保任务和上下文模块能够支持新的 Agent 工作流。

**步骤:**

1. **Task 模块 (`task.lua`):**
    * 增加一个 `is_complete(task_id)` 函数，它检查任务的顶层状态是否为 `completed`。这是 Agent 循环的关键。
    * `update_status` 函数需要能够更新 `todo` 和 `task` 两个层级的状态。

2. **Context 模块 (`context.lua`):**
    * 无需重大修改。它继续负责管理消息历史，包括系统、用户、助手和工具消息。Agent 在每次调用大模型之前，都会从这个模块获取当前的消息列表。

---

## Thought 6: 最终整合、测试与文档更新

**目标:** 确保所有重构后的模块能协同工作，并更新文档以反映新的设计。

**步骤:**

1. **测试:**
    * **场景 1:** 启动 Neovim，执行 `:Doodle` 命令，确认侧边栏出现。
    * **场景 2:** 在输入框输入任务，按回车。确认 Agent 开始执行，并在输出框中流式打印思考过程和结果。
    * **场景 3:** 测试一个需要多步骤（多个 `todo`）的任务，确认 Agent 能按顺序执行并在每个 `todo` 完成后更新状态。
    * **场景 4:** 确认任务完全结束后，Agent 循环正确退出，并输出任务完成的消息。
    * **场景 5:** 在 `lazy.nvim` 配置中添加一个自定义工具，并测试在任务中能否成功调用它。
2. **文档 (`README.md`):**
    * **安装和配置:** 更新 `lazy.nvim` 的配置示例，重点讲解 `opts` 中 `custom_tools` 和 `custom_providers` 的用法。
    * **使用方法:** 解释新的工作流程：使用 `:Doodle` 打开界面，在输入框提交任务。
    * **API 和自定义:** 为希望深度定制的用户提供关于如何编写自定义工具和 Provider 的详细指南。

通过以上六个步骤的修订，`Doodle.nvim` 将拥有一个更加健壮和灵活的架构，完全符合您的最新要求。
