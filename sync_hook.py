#!/usr/bin/env python3
# Minimal REST hook server (no external deps).
# POST /upload with header X-Sync-Token (if SYNC_TOKEN set) triggers "upload only changes" to Backblaze B2 (S3-compatible).
# Body: optional JSON to override defaults:
#   {
#     "path_mode": "models" | "root",        # default "models"
#     "subdir": "checkpoints",               # optional: upload only this subdir under models
#     "include": "*.safetensors,*.ckpt",     # optional, comma-separated
#     "exclude": "*.tmp,*.part",             # optional, comma-separated
#     "concurrency": 64,                     # s5cmd concurrency
#     "delete": false,                       # mirror remote (dangerous) if true; default false
#     "size_only": false,                    # use size-only comparison (awscli fallback)
#     "dry_run": false                       # do not actually upload, just simulate (awscli)
#   }

import json
import os
import shlex
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

HOST = "0.0.0.0"
PORT = 8787

ENV = os.environ
SYNC_TOKEN = ENV.get("SYNC_TOKEN", "")

COMFY_HOME = ENV.get("COMFY_HOME", "/workspace/ComfyUI")
COMFY_MODELS = ENV.get("COMFY_MODELS", "/workspace/ComfyUI/models")

# Required env for upload:
#   AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   B2_ENDPOINT
#   B2_UPLOAD_URL   (s3://bucket/path or s3://bucket)

def have_cmd(name: str) -> bool:
    from shutil import which
    return which(name) is not None

def run(cmd: str) -> int:
    print(f"[sync-hook] RUN: {cmd}", flush=True)
    return subprocess.call(cmd, shell=True)

def upload_with_s5cmd(src_dir: str, remote_url: str, include: list, exclude: list, concurrency: int, delete: bool) -> int:
    src = src_dir.rstrip("/") + "/"
    dst = remote_url.rstrip("/") + "/"
    flags = [f"--endpoint-url {shlex.quote(ENV['B2_ENDPOINT'])}", f"--concurrency {concurrency}", "sync"]
    for p in include:
        if p: flags.append(f"--include {shlex.quote(p)}")
    for p in exclude:
        if p: flags.append(f"--exclude {shlex.quote(p)}")
    if delete:
        flags.append("--delete")
    flags.append(shlex.quote(src) + "*")
    flags.append(shlex.quote(dst))
    return run("s5cmd " + " ".join(flags))

def upload_with_awscli(src_dir: str, remote_url: str, include: list, exclude: list, delete: bool, size_only: bool, dry_run: bool) -> int:
    flags = ["--no-progress", "--only-show-errors", "--exact-timestamps"]
    if delete:
        flags.append("--delete")
    if size_only:
        flags.append("--size-only")
    if dry_run:
        flags.append("--dryrun")
    for p in include:
        if p: flags.extend(["--include", p])
    for p in exclude:
        if p: flags.extend(["--exclude", p])

    cmd = ["aws", "s3", "sync", src_dir, remote_url, "--endpoint-url", ENV["B2_ENDPOINT"], *flags]
    return run(" ".join(shlex.quote(x) for x in cmd))

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != "/upload":
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"Not found")
            return

        # simple token check
        if SYNC_TOKEN:
            token = self.headers.get("X-Sync-Token", "")
            if token != SYNC_TOKEN:
                self.send_response(401)
                self.end_headers()
                self.wfile.write(b"Unauthorized")
                return

        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw.decode("utf-8"))
        except Exception:
            data = {}

        # Validate required env
        for key in ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "B2_ENDPOINT", "B2_UPLOAD_URL"):
            if not ENV.get(key):
                self.send_response(400)
                self.end_headers()
                self.wfile.write(f"Missing env: {key}".encode())
                return

        path_mode = (data.get("path_mode") or "models").lower()
        subdir = data.get("subdir") or ""
        include = [s.strip() for s in (data.get("include") or "").split(",") if s.strip()]
        exclude = [s.strip() for s in (data.get("exclude") or "").split(",") if s.strip()]
        concurrency = int(data.get("concurrency") or 64)
        delete = bool(data.get("delete") or False)
        size_only = bool(data.get("size_only") or False)
        dry_run = bool(data.get("dry_run") or False)

        # Map local->remote
        if path_mode == "models":
            local_base = COMFY_MODELS
            remote = ENV["B2_UPLOAD_URL"].rstrip("/") + "/models"
        elif path_mode == "root":
            local_base = COMFY_MODELS
            remote = ENV["B2_UPLOAD_URL"].rstrip("/")
        else:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b"Invalid path_mode (use 'models' or 'root')")
            return

        if subdir:
            local_base = os.path.join(local_base, subdir)
        os.makedirs(local_base, exist_ok=True)

        # Prefer s5cmd; fallback to awscli
        rc = 1
        if have_cmd("s5cmd"):
            rc = upload_with_s5cmd(local_base, remote, include, exclude, concurrency, delete)
        if rc != 0 and have_cmd("aws"):
            rc = upload_with_awscli(local_base, remote, include, exclude, delete, size_only, dry_run)

        status = 200 if rc == 0 else 500
        self.send_response(status)
        self.end_headers()
        self.wfile.write(json.dumps({"ok": rc == 0, "rc": rc}).encode())

    def log_message(self, fmt, *args):
        # Quieter logs
        return

def main():
    httpd = HTTPServer((HOST, PORT), Handler)
    print(f"[sync-hook] listening on {HOST}:{PORT}", flush=True)
    httpd.serve_forever()

if __name__ == "__main__":
    main()
