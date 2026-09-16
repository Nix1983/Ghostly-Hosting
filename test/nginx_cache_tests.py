"""Exercise cache fallback against an isolated, real Nginx."""
import http.client
import http.server
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = Path(__file__).resolve().parent.parent
NGINX = shutil.which("nginx") or "/usr/sbin/nginx"


def shell(script, *args, check=True):
    return subprocess.run(
        ["bash", "-c", 'source "$1/lib/nginx_cache.sh"\n' + script, "test", str(ROOT), *map(str, args)],
        text=True, capture_output=True, check=check,
    )


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class Upstream(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        status, policy = self.path.strip("/").split("/", 1)
        self.send_response(int(status))
        policies = {
            "public": "public, max-age=31536000, immutable",
            "private": "private, max-age=60",
            "no-cache": "no-cache",
            "no-store": "no-store",
            "empty": "",
        }
        if policy in policies:
            self.send_header("Cache-Control", policies[policy])
        self.send_header("Content-Security-Policy", "default-src 'self'; connect-src 'self' wss:")
        self.send_header("Content-Length", "0")
        if int(status) == 101:
            self.send_header("Upgrade", self.headers.get("Upgrade", ""))
            self.send_header("Connection", self.headers.get("Connection", ""))
        self.end_headers()

    def log_message(self, *args):
        pass


class CachePolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)

    def config(self, site):
        path = self.directory / "nginx.conf"
        path.write_text(
            f'pid {self.directory}/nginx.pid;\nerror_log {self.directory}/error.log;\n'
            f'events {{}}\nhttp {{ access_log off; include "{site}"; }}\n'
        )
        return path

    def test_real_proxy_preserves_policies_and_security_headers(self):
        upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        threading.Thread(target=upstream.serve_forever, daemon=True).start()
        self.addCleanup(upstream.server_close)
        self.addCleanup(upstream.shutdown)
        port = free_port()
        variable = shell('nginx_cache_fallback_variable example.com').stdout
        generated = shell('write_nginx_cache_fallback_map "$2"', variable).stdout
        header = shell('write_nginx_cache_fallback_header "$2"', variable).stdout
        site = self.directory / "site.conf"
        site.write_text(generated + f'''server {{
 listen 127.0.0.1:{port};
 add_header Content-Security-Policy "default-src 'none'";
 add_header X-Inherited unexpected;
 location / {{
  proxy_pass http://127.0.0.1:{upstream.server_port};
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
  {header}
 }}
}}
''')
        config = self.config(site)
        subprocess.run([NGINX, "-t", "-p", str(self.directory), "-c", str(config)], check=True, capture_output=True)
        process = subprocess.Popen([NGINX, "-p", str(self.directory), "-c", str(config), "-g", "daemon off;"], stderr=subprocess.PIPE)
        def stop():
            process.terminate()
            process.communicate(timeout=5)
        self.addCleanup(stop)
        for _ in range(100):
            try:
                with socket.create_connection(("127.0.0.1", port), timeout=.1):
                    break
            except OSError:
                time.sleep(.02)
        for status in (200, 304, 404, 500, 101):
            for policy in ("public", "private", "no-cache", "no-store", "none", "empty"):
                with self.subTest(status=status, policy=policy):
                    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=3)
                    connection.request("GET", f"/{status}/{policy}", headers={"Upgrade": "websocket", "Connection": "upgrade"})
                    response = connection.getresponse()
                    expected = {"public": "public, max-age=31536000, immutable", "private": "private, max-age=60"}.get(policy, policy)
                    headers = [v for k, v in response.getheaders() if k.lower() == "cache-control" and v]
                    self.assertEqual(response.status, status)
                    self.assertEqual(headers, ["no-store" if policy in ("none", "empty") else expected])
                    self.assertIsNone(response.getheader("X-Inherited"))
                    self.assertEqual(response.getheader("Content-Security-Policy"), "default-src 'self'; connect-src 'self' wss:")
                    if status == 101:
                        self.assertEqual(response.getheader("Upgrade"), "websocket")
                        self.assertEqual(response.getheader("Connection").lower(), "upgrade")
                    connection.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
