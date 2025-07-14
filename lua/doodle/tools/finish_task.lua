-- lua/doodle/tools/finish_task.lua
local base = require("doodle.tools.base")
local task = require("doodle.task")
local utils = require("doodle.utils")

local M = {}

-- 创建 finish_task 工具
function M.create()
    return base.BaseTool:new({
        name = "finish_task",
        description = "标记任务完成并退出执行循环",
        parameters = {
            type = "object",
            properties = {
                task_id = {
                    type = "string",
                    description = "任务ID"
                },
                summary = {
                    type = "string",
                    description = "任务完成总结"
                },
                success = {
                    type = "boolean",
                    description = "任务是否成功完成"
                }
            },
            required = {"task_id", "summary"}
        },
        execute = function(args)
            utils.log("info", "执行 finish_task 工具")
            
            -- 验证参数
            if not args.task_id or not args.summary then
                return {
                    success = false,
                    error = "缺少必要参数"
                }
            end
            
            -- 更新任务状态
            local final_status = (args.success == false) and task.TASK_STATUS.FAILED or task.TASK_STATUS.COMPLETED
            local success = task.update_task_status(args.task_id, final_status)
            
            if success then
                return {
                    success = true,
                    message = "任务已完成",
                    summary = args.summary,
                    task_completed = true
                }
            else
                return {
                    success = false,
                    error = "任务完成标记失败"
                }
            end
        end
    })
end

return M 