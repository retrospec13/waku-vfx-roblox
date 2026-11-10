"""Bundle unchanged real modules with explicit mocks; requires the Luau CLI."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MODULES = ['Kit', 'Assets', 'CasterState', 'Pose', 'SelfTest',
           'Effects/PrismCleave', 'Effects/CrystalBloom', 'Effects/StormLance',
           'Effects/EarthRise', 'init']

def main():
    chunks = [(ROOT / 'tests/mocks.luau').read_text()]
    chunks.append('''
local nodes = {}
local loaders, cache = {}, {}
local require
require = function(node)
    assert(node and node.id, "unknown module")
    if cache[node.id] == nil then cache[node.id] = loaders[node.id](node) end
    return cache[node.id]
end
''')
    for name in MODULES + ['PulseOrb']:
        chunks.append(f'nodes["{name}"] = {{id="{name}"}}')
    chunks.append('nodes.init.Effects = {}')
    for name in MODULES:
        if name == 'init':
            continue
        if '/' in name:
            child = name.split('/')[1]
            chunks.append(f'nodes.init.Effects.{child} = nodes["{name}"]; nodes["{name}"].Parent=nodes.init.Effects')
        else:
            chunks.append(f'nodes.init.{name} = nodes["{name}"]; nodes["{name}"].Parent=nodes.init')
    chunks.append('nodes.init.Effects.Parent=nodes.init; nodes.PulseOrb.Parent=nodes.init.Effects')
    for name in MODULES + ['PulseOrb']:
        path = ROOT / ('examples/PulseOrb.luau' if name == 'PulseOrb' else f'src/wakuVFX/{name}.luau')
        chunks.append(f'loaders["{name}"] = function(script)\n' + path.read_text() + '\nend')
    chunks.append((ROOT / 'tests/regressions.luau').read_text())
    with tempfile.TemporaryDirectory(prefix='waku-vfx-regression-', dir=os.environ.get('TMPDIR')) as d:
        path = Path(d) / 'bundled.luau'
        path.write_text('\n'.join(chunks))
        result = subprocess.run(['luau', str(path)], check=False)
        raise SystemExit(result.returncode)

if __name__ == '__main__':
    main()
