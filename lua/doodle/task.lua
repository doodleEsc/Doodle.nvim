-- lua/doodle/task.lua
local utils = require("doodle.utils")
local M = {}

-- 任务状态枚举
M.TASK_STATUS = {
    PENDING = "pending",
    IN_PROGRESS = "in_progress", 
    COMPLETED = "completed",
    FAILED = "failed",
    CANCELLED = "cancelled"
}

-- Todo状态枚举
M.TODO_STATUS = {
    PENDING = "pending",
    IN_PROGRESS = "in_progress",
    COMPLETED = "completed",
    FAILED = "failed",
    SKIPPED = "skipped"
}

-- 当前任务存储
M.current_tasks = {}
M.task_counter = 0

-- 初始化
function M.init(config)
    M.config = config
    M.current_tasks = {}
    M.task_counter = 0
    utils.log("info", "任务模块初始化完成")
end

-- 加载配置
function M.load(config)
    M.init(config)
end

-- 创建新任务
function M.create_task(user_query, description, todos)
    M.task_counter = M.task_counter + 1
    local task_id = "task_" .. M.task_counter
    
    local task = {
        id = task_id,
        user_query = user_query,
        description = description or user_query,
        status = M.TASK_STATUS.PENDING,
        todos = {},
        created_at = utils.get_timestamp(),
        updated_at = utils.get_timestamp(),
        metadata = {}
    }
    
    -- 添加todos
    if todos then
        for i, todo_desc in ipairs(todos) do
            local todo = M.create_todo(todo_desc, i)
            table.insert(task.todos, todo)
        end
    end
    
    M.current_tasks[task_id] = task
    utils.log("info", "创建新任务: " .. task_id)
    
    return task_id
end

-- 创建todo项
function M.create_todo(description, order)
    local todo_id = utils.generate_uuid()
    
    return {
        id = todo_id,
        description = description,
        status = M.TODO_STATUS.PENDING,
        order = order or 1,
        created_at = utils.get_timestamp(),
        updated_at = utils.get_timestamp(),
        result = nil,
        metadata = {}
    }
end

-- 获取任务
function M.get_task(task_id)
    return M.current_tasks[task_id]
end

-- 获取所有任务
function M.get_all_tasks()
    return M.current_tasks
end

-- 更新任务状态
function M.update_task_status(task_id, status)
    local task = M.current_tasks[task_id]
    if not task then
        utils.log("error", "任务不存在: " .. task_id)
        return false
    end
    
    task.status = status
    task.updated_at = utils.get_timestamp()
    
    utils.log("info", "更新任务状态: " .. task_id .. " -> " .. status)
    return true
end

-- 更新todo状态
function M.update_todo_status(task_id, todo_id, status, result)
    local task = M.current_tasks[task_id]
    if not task then
        utils.log("error", "任务不存在: " .. task_id)
        return false
    end
    
    local todo = M.find_todo(task, todo_id)
    if not todo then
        utils.log("error", "Todo不存在: " .. todo_id)
        return false
    end
    
    todo.status = status
    todo.updated_at = utils.get_timestamp()
    if result then
        todo.result = result
    end
    
    -- 更新任务的更新时间
    task.updated_at = utils.get_timestamp()
    
    utils.log("info", "更新Todo状态: " .. todo_id .. " -> " .. status)
    return true
end

-- 查找todo
function M.find_todo(task, todo_id)
    for _, todo in ipairs(task.todos) do
        if todo.id == todo_id then
            return todo
        end
    end
    return nil
end

-- 获取下一个待执行的todo
function M.get_next_todo(task_id)
    local task = M.current_tasks[task_id]
    if not task then
        return nil
    end
    
    -- 按order排序并找到第一个未完成的todo
    table.sort(task.todos, function(a, b) return a.order < b.order end)
    
    for _, todo in ipairs(task.todos) do
        if todo.status == M.TODO_STATUS.PENDING then
            return todo
        end
    end
    
    return nil
end

-- 检查任务是否完成
function M.is_task_complete(task_id)
    local task = M.current_tasks[task_id]
    if not task then
        return false
    end
    
    return task.status == M.TASK_STATUS.COMPLETED
end

-- 检查所有todos是否完成
function M.are_all_todos_complete(task_id)
    local task = M.current_tasks[task_id]
    if not task then
        return false
    end
    
    for _, todo in ipairs(task.todos) do
        if todo.status ~= M.TODO_STATUS.COMPLETED and todo.status ~= M.TODO_STATUS.SKIPPED then
            return false
        end
    end
    
    return true
end

-- 获取任务进度
function M.get_task_progress(task_id)
    local task = M.current_tasks[task_id]
    if not task then
        return 0
    end
    
    if #task.todos == 0 then
        return 0
    end
    
    local completed_count = 0
    for _, todo in ipairs(task.todos) do
        if todo.status == M.TODO_STATUS.COMPLETED or todo.status == M.TODO_STATUS.SKIPPED then
            completed_count = completed_count + 1
        end
    end
    
    return completed_count / #task.todos
end

-- 添加todo到任务
function M.add_todo(task_id, description)
    local task = M.current_tasks[task_id]
    if not task then
        utils.log("error", "任务不存在: " .. task_id)
        return false
    end
    
    local order = #task.todos + 1
    local todo = M.create_todo(description, order)
    table.insert(task.todos, todo)
    
    task.updated_at = utils.get_timestamp()
    
    utils.log("info", "添加Todo到任务: " .. task_id)
    return todo.id
end

-- 移除todo
function M.remove_todo(task_id, todo_id)
    local task = M.current_tasks[task_id]
    if not task then
        utils.log("error", "任务不存在: " .. task_id)
        return false
    end
    
    for i, todo in ipairs(task.todos) do
        if todo.id == todo_id then
            table.remove(task.todos, i)
            task.updated_at = utils.get_timestamp()
            utils.log("info", "移除Todo: " .. todo_id)
            return true
        end
    end
    
    return false
end

-- 获取任务摘要
function M.get_task_summary(task_id)
    local task = M.current_tasks[task_id]
    if not task then
        return nil
    end
    
    local summary = {
        id = task.id,
        description = task.description,
        status = task.status,
        progress = M.get_task_progress(task_id),
        total_todos = #task.todos,
        completed_todos = 0,
        pending_todos = 0,
        created_at = task.created_at,
        updated_at = task.updated_at
    }
    
    -- 统计todos状态
    for _, todo in ipairs(task.todos) do
        if todo.status == M.TODO_STATUS.COMPLETED or todo.status == M.TODO_STATUS.SKIPPED then
            summary.completed_todos = summary.completed_todos + 1
        elseif todo.status == M.TODO_STATUS.PENDING then
            summary.pending_todos = summary.pending_todos + 1
        end
    end
    
    return summary
end

-- 获取任务详情
function M.get_task_details(task_id)
    local task = M.current_tasks[task_id]
    if not task then
        return nil
    end
    
    local details = utils.deep_copy(task)
    details.progress = M.get_task_progress(task_id)
    details.summary = M.get_task_summary(task_id)
    
    return details
end

-- 清理完成的任务
function M.cleanup_completed_tasks()
    local completed_tasks = {}
    
    for task_id, task in pairs(M.current_tasks) do
        if task.status == M.TASK_STATUS.COMPLETED or task.status == M.TASK_STATUS.FAILED then
            table.insert(completed_tasks, task_id)
        end
    end
    
    for _, task_id in ipairs(completed_tasks) do
        M.current_tasks[task_id] = nil
        utils.log("info", "清理完成的任务: " .. task_id)
    end
    
    return #completed_tasks
end

-- 取消任务
function M.cancel_task(task_id)
    local task = M.current_tasks[task_id]
    if not task then
        utils.log("error", "任务不存在: " .. task_id)
        return false
    end
    
    task.status = M.TASK_STATUS.CANCELLED
    task.updated_at = utils.get_timestamp()
    
    -- 取消所有未完成的todos
    for _, todo in ipairs(task.todos) do
        if todo.status == M.TODO_STATUS.PENDING or todo.status == M.TODO_STATUS.IN_PROGRESS then
            todo.status = M.TODO_STATUS.SKIPPED
            todo.updated_at = utils.get_timestamp()
        end
    end
    
    utils.log("info", "取消任务: " .. task_id)
    return true
end

-- 重置任务
function M.reset_task(task_id)
    local task = M.current_tasks[task_id]
    if not task then
        utils.log("error", "任务不存在: " .. task_id)
        return false
    end
    
    task.status = M.TASK_STATUS.PENDING
    task.updated_at = utils.get_timestamp()
    
    -- 重置所有todos
    for _, todo in ipairs(task.todos) do
        todo.status = M.TODO_STATUS.PENDING
        todo.updated_at = utils.get_timestamp()
        todo.result = nil
    end
    
    utils.log("info", "重置任务: " .. task_id)
    return true
end

-- 获取活跃任务
function M.get_active_tasks()
    local active_tasks = {}
    
    for task_id, task in pairs(M.current_tasks) do
        if task.status == M.TASK_STATUS.PENDING or task.status == M.TASK_STATUS.IN_PROGRESS then
            table.insert(active_tasks, task)
        end
    end
    
    return active_tasks
end

-- 验证任务结构
function M.validate_task(task)
    if type(task) ~= "table" then
        return false, "任务必须是表类型"
    end
    
    if utils.is_string_empty(task.description) then
        return false, "任务必须有描述"
    end
    
    if not task.todos or type(task.todos) ~= "table" then
        return false, "任务必须有todos列表"
    end
    
    return true
end

-- 导出任务数据
function M.export_task_data()
    local export_data = {
        tasks = M.current_tasks,
        task_counter = M.task_counter,
        exported_at = utils.get_timestamp()
    }
    
    return export_data
end

-- 导入任务数据
function M.import_task_data(data)
    if not data or type(data) ~= "table" then
        return false, "无效的导入数据"
    end
    
    if data.tasks then
        M.current_tasks = data.tasks
    end
    
    if data.task_counter then
        M.task_counter = data.task_counter
    end
    
    utils.log("info", "导入任务数据完成")
    return true
end

return M 