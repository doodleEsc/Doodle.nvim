-- debug_tools_format.lua
-- 调试工具格式的辅助函数

local M = {}

-- 检查 tools 格式
function M.debug_tools_format(tools, context)
    print("\n=== DEBUG TOOLS FORMAT (" .. (context or "unknown") .. ") ===")
    
    if not tools then
        print("❌ tools 为 nil")
        return
    end
    
    print("📋 tools 类型:", type(tools))
    
    if type(tools) == "table" then
        -- 检查是否为数组
        local is_array = true
        local count = 0
        for k, v in pairs(tools) do
            count = count + 1
            if type(k) ~= "number" then
                is_array = false
                break
            end
        end
        
        print("📊 元素数量:", count)
        print("🔢 是否为数组:", is_array and "✅" or "❌")
        
        if is_array and count > 0 then
            print("🔍 第一个元素:")
            local first = tools[1]
            if type(first) == "table" then
                print("  - type:", first.type or "❌ 缺失")
                if first["function"] then
                    print("  - function.name:", first["function"].name or "❌ 缺失")
                    print("  - function.description:", first["function"].description and "✅" or "❌ 缺失")
                    print("  - function.parameters:", first["function"].parameters and "✅" or "❌ 缺失")
                else
                    print("  - function: ❌ 缺失")
                end
            else
                print("  ❌ 第一个元素不是 table")
            end
        elseif not is_array then
            print("🗝️  Key-Value 结构 (可能错误):")
            for k, v in pairs(tools) do
                print("  - key:", k, "type:", type(v))
            end
        end
    else
        print("❌ tools 不是 table")
    end
    
    print("=== END DEBUG ===\n")
end

-- 在各个 provider 的 request 函数开始处添加这个调用：
-- require("debug_tools_format").debug_tools_format(options.tools, "Provider名称")

return M 