-- lua/doodle/tools/update_task.lua
local base = require("doodle.tools.base")
local task = require("doodle.task")
local utils = require("doodle.utils")

local M = {}

-- 创建 update_task 工具
function M.create()
    return base.BaseTool:new({
        name = "update_task",
        description = "更新任务中todo项的状态",
        parameters = {
            type = "object",
            properties = {
                task_id = {
                    type = "string",
                    description = "任务ID"
                },
                todo_id = {
                    type = "string",
                    description = "Todo项ID"
                },
                status = {
                    type = "string",
                    enum = {"pending", "in_progress", "completed", "failed", "skipped"},
                    description = "新的状态"
                },
                result = {
                    type = "string",
                    description = "执行结果或备注"
                }
            },
            required = {"task_id", "todo_id", "status"}
        },
        execute = function(args)
            utils.log("info", "执行 update_task 工具")
            
            -- 验证参数
            if not args.task_id or not args.todo_id or not args.status then
                return {
                    success = false,
                    error = "缺少必要参数"
                }
            end
            
            -- 更新todo状态
            local success = task.update_todo_status(args.task_id, args.todo_id, args.status, args.result)
            
            if success then
                -- 检查是否所有todo都已完成
                if task.are_all_todos_complete(args.task_id) then
                    task.update_task_status(args.task_id, task.TASK_STATUS.COMPLETED)
                    return {
                        success = true,
                        message = "Todo状态更新成功，所有任务已完成",
                        task_completed = true
                    }
                else
                    return {
                        success = true,
                        message = "Todo状态更新成功",
                        task_completed = false
                    }
                end
            else
                return {
                    success = false,
                    error = "Todo状态更新失败"
                }
            end
        end
    })
end

return M 