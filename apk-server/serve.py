#!/usr/bin/env python3
"""
Simple APK Download Server
รัน: python3 serve.py [port]
"""

import http.server
import socketserver
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
SERVE_DIR = os.path.dirname(os.path.abspath(__file__))


class APKHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=SERVE_DIR, **kwargs)

    def end_headers(self):
        # Force download for APK files
        if self.path.endswith('.apk'):
            self.send_header('Content-Type', 'application/vnd.android.package-archive')
            self.send_header('Content-Disposition', 'attachment')
        super().end_headers()

    def log_message(self, format, *args):
        print(f"[{self.address_string()}] {format % args}")


with socketserver.TCPServer(("", PORT), APKHandler) as httpd:
    print(f"🃏 The Sun Poker - APK Download Server")
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    print(f"✅ Server running at: http://localhost:{PORT}")
    print(f"")
    print(f"📱 Download links:")
    print(f"   http://localhost:{PORT}/apk/the-sun-poker-arm64.apk")
    print(f"   http://localhost:{PORT}/apk/the-sun-poker-armv7.apk")
    print(f"   http://localhost:{PORT}/apk/the-sun-poker-x86_64.apk")
    print(f"")
    print(f"Press Ctrl+C to stop")
    print(f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    httpd.serve_forever()
