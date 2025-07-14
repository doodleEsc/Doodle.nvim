-- lua/doodle/tools/think_task.lua
local base = require("doodle.tools.base")
local task = require("doodle.task")
local utils = require("doodle.utils")

local M = {}

-- 创建 think_task 工具
function M.create()
    return base.BaseTool:new({
        name = "think_task",
        description = "分析用户请求并将其分解为具体的任务和todo项",
        parameters = {
            type = "object",
            properties = {
                user_query = {
                    type = "string",
                    description = "用户的原始请求"
                },
                analysis = {
                    type = "string", 
                    description = "对用户请求的分析和理解"
                },
                task_description = {
                    type = "string",
                    description = "任务的总体描述"
                },
                todos = {
                    type = "array",
                    items = {
                        type = "string"
                    },
                    description = "具体的todo项目列表"
                }
            },
            required = {"user_query", "analysis", "task_description", "todos"}
        },
        execute = function(args)
            utils.log("info", "执行 think_task 工具")
            
            -- 验证参数
            if not args.user_query or not args.task_description or not args.todos then
                return {
                    success = false,
                    error = "缺少必要参数"
                }
            end
            
            -- 创建任务
            local task_id = task.create_task(args.user_query, args.task_description, args.todos)
            
            if task_id then
                -- 更新任务状态为进行中
                task.update_task_status(task_id, task.TASK_STATUS.IN_PROGRESS)
                
                return {
                    success = true,
                    task_id = task_id,
                    message = "任务创建成功，包含 " .. #args.todos .. " 个待办事项",
                    analysis = args.analysis,
                    task_description = args.task_description,
                    todos = args.todos
                }
            else
                return {
                    success = false,
                    error = "任务创建失败"
                }
            end
        end
    })
end

return M 