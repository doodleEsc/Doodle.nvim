-- lua/doodle/utils.lua
local M = {}

-- 配置引用
M.config = nil

-- 初始化
function M.init(config)
    M.config = config
end

-- 日志功能
function M.log(level, msg)
    if not M.config or not M.config.debug then
        return
    end
    
    local levels = {
        debug = 1,
        info = 2,
        warn = 3,
        error = 4,
    }
    
    local config_level = levels[M.config.log_level] or 2
    local msg_level = levels[level] or 2
    
    if msg_level >= config_level then
        print(string.format("[Doodle.nvim] [%s] %s", level:upper(), msg))
    end
end

-- 深度复制表
function M.deep_copy(orig)
    local copy
    if type(orig) == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[M.deep_copy(orig_key)] = M.deep_copy(orig_value)
        end
        setmetatable(copy, M.deep_copy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- 检查表是否为空
function M.is_empty(t)
    return next(t) == nil
end

-- 生成UUID
function M.generate_uuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

-- 获取当前时间戳
function M.get_timestamp()
    return os.time()
end

-- 字符串分割
function M.split(str, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for token in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(t, token)
    end
    return t
end

-- 字符串去除空白
function M.trim(str)
    return str:match("^%s*(.-)%s*$")
end

-- 检查字符串是否为空
function M.is_string_empty(str)
    return str == nil or str == "" or M.trim(str) == ""
end

-- 安全的表访问
function M.safe_get(t, key, default)
    if type(t) ~= "table" then
        return default
    end
    return t[key] or default
end

-- 错误处理包装器
function M.safe_call(fn, ...)
    local success, result = pcall(fn, ...)
    if not success then
        M.log("error", "函数调用失败: " .. tostring(result))
        return nil, result
    end
    return result
end

-- 异步延迟
function M.delay(ms, callback)
    vim.defer_fn(callback, ms)
end

-- 检查是否在 Neovim 中
function M.is_neovim()
    return vim ~= nil
end

-- 获取缓冲区内容
function M.get_buffer_content(bufnr)
    bufnr = bufnr or 0
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    return table.concat(lines, '\n')
end

-- 获取选中文本
function M.get_visual_selection()
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getline(start_pos[2], end_pos[2])
    
    if #lines == 0 then
        return ""
    end
    
    if #lines == 1 then
        return string.sub(lines[1], start_pos[3], end_pos[3])
    end
    
    lines[1] = string.sub(lines[1], start_pos[3])
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[3])
    
    return table.concat(lines, '\n')
end

-- 获取当前文件路径
function M.get_current_file()
    return vim.fn.expand("%:p")
end

-- 获取当前目录
function M.get_current_dir()
    return vim.fn.getcwd()
end

-- 格式化消息
function M.format_message(msg_type, content, metadata)
    return {
        type = msg_type,
        content = content,
        metadata = metadata or {},
        timestamp = M.get_timestamp(),
        id = M.generate_uuid(),
    }
end

-- 验证工具结构
function M.validate_tool(tool)
    if type(tool) ~= "table" then
        return false, "工具必须是表类型"
    end
    
    if M.is_string_empty(tool.name) then
        return false, "工具必须有名称"
    end
    
    if M.is_string_empty(tool.description) then
        return false, "工具必须有描述"
    end
    
    if type(tool.execute) ~= "function" then
        return false, "工具必须有execute函数"
    end
    
    return true
end

-- 验证Provider结构
function M.validate_provider(provider)
    if type(provider) ~= "table" then
        return false, "Provider必须是表类型"
    end
    
    if M.is_string_empty(provider.name) then
        return false, "Provider必须有名称"
    end
    
    if type(provider.request) ~= "function" then
        return false, "Provider必须有request函数"
    end
    
    if M.is_string_empty(provider.base_url) then
        return false, "Provider必须指定base_url"
    end
    
    if M.is_string_empty(provider.model) then
        return false, "Provider必须指定model"
    end
    
    return true
end

return M 