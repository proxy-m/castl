--[[
    Copyright (c) 2014, Paul Bernier
    
    CASTL is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.
    CASTL is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.
    You should have received a copy of the GNU Lesser General Public License
    along with CASTL. If not, see <http://www.gnu.org/licenses/>.
--]]

local castl, esprima, runtime
local luajit = jit ~= nil

local eval = {}

local debug, setmetatable, assert, load, error, require = debug, setmetatable, assert, load, error, require

_ENV = nil

-- http://stackoverflow.com/a/2835433/1120148
local locals = function(level)
    local variables = {}
    local idx = 1
    while true do
        local ln, lv = debug.getlocal(level, idx)
        if ln ~= nil then
            variables[ln] = lv
        else
            break
        end
        idx = 1 + idx
    end
    return variables
end

local upvalues = function(level)
    local variables = {}
    local idx = 1
    local func = debug.getinfo(level, "f").func
    while true do
        local ln, lv = debug.getupvalue(func, idx)
        if ln ~= nil then
            variables[ln] = lv
        else
            break
        end
        idx = 1 + idx
    end
    return variables
end

local getEvalENV = function(locals, upvalues, globals)
    return setmetatable({},{
        __index = function(self, key)
            if locals[key] then
                return locals[key]
            elseif upvalues[key] then
                return upvalues[key]
            else
                return globals[key]
            end
        end,
        __newindex = function(self, key, value)
            if locals[key] then
                locals[key] = value
            elseif upvalues[key] then
                upvalues[key] = value
            else
                globals[key] = value
            end
        end
    })
end

local evalLuaString = function(str, _G)
    local level = 4

    -- collect locals and upvalues
    local _l = locals(level)
    local _u = upvalues(level)
    local _evalENV = getEvalENV(_l, _u, _G)

    -- eval lua code
    local evaluated = assert(load(str, nil, "t", _evalENV))
    local lastReturn, value
    local catch = function()
        value = lastReturn
        local _, v = debug.getlocal(2,1)
        lastReturn = v
    end

    -- catch the last return
    debug.sethook(catch, "r")
    evaluated()
    debug.sethook()

    -- set upvalues
    local _idx = 1
    local _func = debug.getinfo(level - 1, "f").func
    while true do
        local ln = debug.getupvalue(_func, _idx)
        if ln ~= nil then
            if ln ~= "(*temporary)" and _u[ln] then
                debug.setupvalue(_func, _idx, _u[ln])
            end

        else
            break
        end
        _idx = 1 + _idx
    end

    -- set locals
    _idx = 1
    while true do
        local ln = debug.getlocal(level - 1, _idx)
        if ln ~= nil then
            if ln ~= "(*temporary)" and _l[ln] then
                debug.setlocal(level - 1, _idx, _l[ln])
            end
        else
            break
        end
        _idx = 1 + _idx
    end

    return value
end

function eval.eval(this, str)
    runtime = runtime or require("castl.runtime")

    if luajit then
        castl = castl or require("castl.jscompile.castl_jit")
        esprima = esprima or require("castl.jscompile.esprima_jit")
    else
        castl = castl or require("castl.jscompile.castl")
        esprima = esprima or require("castl.jscompile.esprima")
    end

    -- parse and compile JS code
    local ast = esprima:parse(str)
    local castlResult = castl:compileAST(ast)
    local ret

    if castlResult.success then
        local luaCode = castlResult.compiled
        ret = evalLuaString(luaCode, runtime)
    else
        error("Eval(): Failed to compile AST to Lua code")
    end

    return ret
end

return eval
