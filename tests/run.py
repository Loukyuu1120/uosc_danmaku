"""Offline regressions under mpv-compatible Lua 5.1 and LuaJIT.

Install the test dependency with: python -m pip install lupa
Run from the repository root: python tests/run.py
"""
import json
import os
from pathlib import Path
import tempfile
import subprocess
import zipfile

from lupa import lua51, lua52, luajit21
from regex_cases import verify_regex
from transport import verify_proxy_transport

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)


def run(engine):
    with tempfile.TemporaryDirectory(prefix='uosc-regression-') as directory:
        root = Path(directory).resolve()
        assert root.parent == Path(tempfile.gettempdir()).resolve()
        run_in_fixture(engine, root)


def run_in_fixture(engine, test_root):
    lua = engine.LuaRuntime(unpack_returned_tuples=True)

    def to_lua(value):
        if isinstance(value, dict):
            return lua.table_from({k: to_lua(v) for k, v in value.items()})
        if isinstance(value, list):
            return lua.table_from([to_lua(v) for v in value])
        return value

    def to_python(value):
        if hasattr(value, 'items'):
            keys = list(value.keys())
            if keys and all(isinstance(k, int) for k in keys):
                return [to_python(value[i]) for i in range(1, len(keys) + 1)]
            return {k: to_python(v) for k, v in value.items()}
        return value

    def parse(text):
        try:
            return to_lua(json.loads(text))
        except (TypeError, ValueError):
            return None

    lua.globals().py_parse_json = parse
    lua.globals().py_format_json = lambda value: json.dumps(to_python(value), ensure_ascii=False)
    lua.globals().py_file_info = lambda p: to_lua({'is_file': True, 'size': Path(p).stat().st_size}) if p and Path(p).is_file() else None
    for size in (16 * 1024 * 1024 - 1, 16 * 1024 * 1024, 16 * 1024 * 1024 + 1):
        with (test_root / (str(size) + '.mkv')).open('wb') as stream:
            stream.truncate(size)
    lua.globals().test_root = str(test_root).replace('\\', '/')
    lua.execute((ROOT / 'tests/harness.lua').read_text(encoding='utf-8'))
    compile_lua = lua.eval('function(s,n) local f,e=(loadstring or load)(s,n); assert(f,e) end')
    for path in ROOT.rglob('*.lua'):
        compile_lua(path.read_text(encoding='utf-8'), str(path))
    lua.execute("dofile('main.lua')")
    lua.execute((ROOT / 'tests/regression.lua').read_text(encoding='utf-8'))
    lua.execute((ROOT / 'tests/imports.lua').read_text(encoding='utf-8'))
    verify_regex(lua)
    verify_proxy_transport(lua, test_root)
    if engine is luajit21:
        verify_updater(lua, test_root)
    print(engine.__name__ + ': all regressions passed')


def verify_updater(lua, root):
    lua.globals().test_platform = 'windows' if os.name == 'nt' else 'linux'
    lua.execute("""
        local original_get_property = mp.get_property
        mp.get_property = function(name, default)
            if name == 'platform' then return test_platform end
            return original_get_property(name, default)
        end
        package.loaded['modules/update'] = nil
        require('modules/update')
    """)
    for scenario in ('flat', 'nested', 'incomplete', 'missing_dependency', 'corrupt', 'swap_failure'):
        target = root / scenario / 'uosc_danmaku'
        target.mkdir(parents=True)
        (target / 'main.lua').write_text('old version', encoding='utf-8')
        lua.globals().update_target = str(target).replace('\\', '/')
        lua.execute("mp.get_script_directory = function() return update_target end; check_for_update()")
        request_id = len(lua.globals().pending)
        lua.globals().respond(request_id, '{"tag_name":"v99.0.0","assets":[{"browser_download_url":"https://example.test/update.zip"}]}')
        download_id = len(lua.globals().pending)
        download_args = list(lua.globals().pending[download_id]['command']['args'].values())
        archive = Path(download_args[download_args.index('-o') + 1]).resolve()
        assert archive.is_relative_to(root.resolve()), 'test archive escaped fixture directory'
        if scenario == 'corrupt':
            archive.write_bytes(b'not a ZIP archive')
        else:
            with zipfile.ZipFile(archive, 'w') as package:
                prefix = 'uosc_danmaku/' if scenario == 'nested' else ''
                required = ['main.lua'] + [p.relative_to(ROOT).as_posix()
                    for directory in ('modules', 'apis', 'sites', 'dicts')
                    for p in (ROOT / directory).glob('*.lua')]
                for path in required[:1] if scenario == 'incomplete' else required:
                    if scenario == 'missing_dependency' and path == 'modules/regex.lua':
                        continue
                    package.writestr(prefix + path, 'new version')
        lua.globals().respond(download_id, '')
        swap_id = len(lua.globals().pending)
        swap_args = list(lua.globals().pending[swap_id]['command']['args'].values())
        if scenario == 'swap_failure':
            if os.name == 'nt':
                swap_args[-1] = swap_args[-1].replace(
                    'try { Move-Item -LiteralPath $stage -Destination $target }',
                    "try { throw 'simulated swap failure' }")
            else:
                swap_args[2] = swap_args[2].replace('if ! mv "$stage" "$target"; then', 'if ! false; then')
        result = subprocess.run(swap_args, capture_output=True, text=True, timeout=30)
        lua.globals().respond(swap_id, result.stdout, result.returncode)
        expected = 'new version' if scenario in ('flat', 'nested') else 'old version'
        assert (target / 'main.lua').read_text(encoding='utf-8') == expected, scenario + ': original installation lost'
        if scenario in ('flat', 'nested'):
            backups = list(target.parent.glob('uosc_danmaku.backup-*'))
            assert any((p / 'main.lua').is_file() and (p / 'main.lua').read_text() == 'old version' for p in backups)
    print(('Windows' if os.name == 'nt' else 'Unix') + ' updater: flat/nested, corrupt/incomplete/missing dependency, and rollback passed')


for runtime in (lua51, lua52, luajit21):
    run(runtime)
