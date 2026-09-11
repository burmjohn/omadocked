"""Owned compositor double: execute actual Lua, never parse action text.

Hyprland v0.56.2 factories construct non-callable dispatcher objects. Only
hl.dispatch executes them. This proves controller/API semantics, not native moves.
"""
import json
import subprocess


def execute_moves(code, clients):
    windows = []
    for client in clients:
        generation = client.get('stableId')
        windows.append('{address=' + json.dumps(client['address']) + ',stable_id=' +
                       ('0x' + generation if generation else 'nil') + '}')
    stub = '''local windows={%s}
local moves={}
hl={get_windows=function() return windows end,
    dsp={window={move=function(args) return {args=args} end}},
    dispatch=function(dispatcher)
        assert(type(dispatcher)=='table' and dispatcher.args)
        local args=dispatcher.args
        for i,w in ipairs(windows) do
            if 'address:'..w.address==args.window then
                table.insert(moves,{index=i,workspace=args.workspace})
            end
        end
    end}
''' % ','.join(windows)
    output = '''
for _,m in ipairs(moves) do
    local hex=m.workspace:gsub('.',function(c) return string.format('%%02x',string.byte(c)) end)
    print(m.index..':'..hex)
end
'''.replace('%%02x', '%02x')
    result = subprocess.run(['/usr/bin/lua', '-'], input=stub + code + output,
                            text=True, capture_output=True, timeout=3, check=True)
    return [(int(line.split(':')[0]) - 1, bytes.fromhex(line.split(':')[1]).decode())
            for line in result.stdout.splitlines()]
