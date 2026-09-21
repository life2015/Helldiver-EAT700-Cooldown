"""Run/compile Lua using the user's matching game LuaJIT in this build process.

Does not connect to, launch, or inject into the game. No DLL is distributed.
"""
import ctypes as C
from pathlib import Path


class Lua:
    def __init__(self, dll):
        self.lib = l = C.CDLL(str(dll))
        l.luaL_newstate.restype = C.c_void_p
        l.luaL_openlibs.argtypes = [C.c_void_p]
        l.luaL_loadbuffer.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t, C.c_char_p]
        l.lua_pcall.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int]
        l.lua_tolstring.argtypes = [C.c_void_p, C.c_int, C.POINTER(C.c_size_t)]
        l.lua_tolstring.restype = C.c_void_p
        l.lua_settop.argtypes = [C.c_void_p, C.c_int]
        l.lua_close.argtypes = [C.c_void_p]
        self.state = l.luaL_newstate()
        if not self.state:
            raise RuntimeError('Cannot create Lua state')
        l.luaL_openlibs(self.state)
        self.run("assert(not require('ffi').abi('gc64'), 'non-GC64 LuaJIT required')")

    def run(self, source, name='@build'):
        data = source.encode() if isinstance(source, str) else source
        l, s = self.lib, self.state
        l.lua_settop(s, 0)
        status = l.luaL_loadbuffer(s, data, len(data), name.encode()) or l.lua_pcall(s, 0, 1, 0)
        n = C.c_size_t()
        ptr = l.lua_tolstring(s, -1, C.byref(n))
        result = C.string_at(ptr, n.value) if ptr else b''
        if status:
            raise RuntimeError(result.decode('utf-8', 'replace'))
        return result

    def compile(self, source):
        bytecode = self.run('return string.dump(assert(loadstring(' + literal(source.encode()) + ")),true)")
        if bytecode[:5] != b'\x1bLJ\x02\x02':
            raise ValueError('Incompatible LuaJIT bytecode')
        return bytecode

    def close(self):
        self.lib.lua_close(self.state)


def literal(data):
    return '"' + ''.join('\\%03d' % n for n in data) + '"'
