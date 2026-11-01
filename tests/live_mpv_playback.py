"""Exercise search -> select episode -> render with the user's API/load options.

Uses a generated video and a temporary config; never loads the user's media.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(mpv_dir, plugin_dir, ffmpeg, timeout, menu=False):
    actual = {}
    for line in (mpv_dir / 'portable_config/script-opts/uosc_danmaku.conf').read_text(encoding='utf-8-sig').splitlines():
        if '=' not in line or line.lstrip().startswith('#'):
            continue
        key, value = (part.strip() for part in line.split('=', 1))
        if key in ('api_servers', 'api_server', 'proxy', 'user_agent'):
            actual[key] = value
        elif key in ('load_more_danmaku', 'hash_for_url'):
            actual[key] = value.lower() == 'yes'
    with tempfile.TemporaryDirectory(prefix='uosc-playback-test-') as directory:
        work = Path(directory)
        config = work / 'config'
        config.mkdir()
        video, report, settings = work / 'Show S01E01.mkv', work / 'report.json', work / 'options.json'
        settings.write_text(json.dumps(actual, ensure_ascii=False), encoding='utf-8')
        subprocess.run([str(ffmpeg), '-v', 'error', '-f', 'lavfi', '-i', 'color=c=black:s=640x360:r=24',
                        '-t', '65', '-c:v', 'libx264', '-preset', 'ultrafast', str(video)],
                       check=True, capture_output=True)
        options = ','.join('live_mpv_playback-' + key + '=' + str(value) for key, value in
                           [('plugin', plugin_dir.as_posix()), ('report', report.as_posix()),
                            ('options_path', settings.as_posix()), ('timeout', timeout), ('menu', 'yes' if menu else 'no')])
        subprocess.run([str(mpv_dir / 'mpv.exe'), '--config-dir=' + str(config), '--load-scripts=no',
                        '--vo=null', '--ao=null', '--force-window=no',
                        '--script=' + str(ROOT / 'tests/live_mpv_playback.lua'), '--script-opts=' + options,
                        str(video)], cwd=work, capture_output=True, timeout=timeout + 5,
                       creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        return json.loads(report.read_text(encoding='utf-8')) if report.exists() else {'missing_report': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mpv-dir', type=Path, required=True)
    parser.add_argument('--plugin-dir', type=Path, default=ROOT)
    parser.add_argument('--ffmpeg', type=Path, required=True)
    parser.add_argument('--timeout', type=int, default=45)
    parser.add_argument('--menu', action='store_true')
    args = parser.parse_args()
    print(json.dumps(run(args.mpv_dir, args.plugin_dir, args.ffmpeg, args.timeout, args.menu), ensure_ascii=True, indent=2))
