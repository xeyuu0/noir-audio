#!/usr/bin/env python3
"""Local static preview with Vercel-like clean HTML URLs. Loopback interface only."""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent / "public"

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        path = urlsplit(self.path).path
        if path != "/" and not Path(path).suffix and (ROOT / (path.lstrip("/") + ".html")).is_file():
            self.path = path + ".html"
        return super().do_GET()

if __name__ == "__main__":
    print("NOIR website preview: http://127.0.0.1:4173", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 4173), Handler).serve_forever()
