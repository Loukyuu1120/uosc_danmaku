"""Use a local HTTP proxy to verify actual curl routing without external traffic."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading


def verify_proxy_transport(lua, fixture):
    requests = []

    class Proxy(BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append((self.path, self.headers.get('Cookie')))
            self.send_response(200)
            self.send_header('Content-Length', '8')
            self.end_headers()
            self.wfile.write(b'proxy-ok')

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Proxy)
    thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.01}, daemon=True)
    thread.start()
    lua.globals().probe_proxy = f'http://127.0.0.1:{server.server_port}'
    cookie = Path(fixture) / 'transport-cookies.txt'
    cookie.write_text('# Netscape HTTP Cookie File\nmgtv.com\tFALSE\t/\tFALSE\t2147483647\tfixture_cookie\tyes\n', encoding='utf-8')
    lua.globals().probe_cookie = cookie.as_posix()
    try:
        lua.execute("options.proxy = probe_proxy")
        for url, use_cookie in [('http://mgtv.com/proxy-probe', True), ('http://api.github.com/proxy-probe', False)]:
            lua.globals().probe_url = url
            lua.globals().probe_with_cookie = use_cookie
            lua.execute("""
                local args = {'curl', '--noproxy', '', '-sS', '--max-time', '5'}
                if probe_with_cookie then args[#args+1] = '-b'; args[#args+1] = probe_cookie end
                args[#args+1] = probe_url
                call_cmd_async(args, function() end)
            """)
            request_id = len(lua.globals().pending)
            args = list(lua.globals().pending[request_id]['command']['args'].values())
            result = subprocess.run(args, capture_output=True, timeout=10)
            assert result.returncode == 0, result.stderr
            assert result.stdout == b'proxy-ok', result.stdout
            lua.globals().respond(request_id, result.stdout.decode())
        assert requests == [('http://mgtv.com/proxy-probe', 'fixture_cookie=yes'),
                            ('http://api.github.com/proxy-probe', None)], requests
    finally:
        lua.execute("options.proxy = ''; fire('end-file')")
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
    print('Local HTTP proxy: real curl routing and cookie scope passed')
