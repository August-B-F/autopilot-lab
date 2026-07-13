#!/usr/bin/env python3
"""Parameterized VPS SSH helper (paramiko, password auth).

Credentials come from environment variables so nothing is hardcoded in the repo:
    VPS_HOST, VPS_USER (default root), VPS_PASS, VPS_PORT (default 22)

Usage:  python vps_ssh.py "<remote command>" [timeout_seconds]
"""
import os
import sys
import paramiko

HOST = os.environ.get("VPS_HOST")
USER = os.environ.get("VPS_USER", "root")
PASS = os.environ.get("VPS_PASS")
PORT = int(os.environ.get("VPS_PORT", "22"))


def run(cmd, timeout=120):
    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(HOST, port=PORT, username=USER, password=PASS,
              timeout=15, allow_agent=False, look_for_keys=False)
    _, stdout, stderr = c.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    c.close()
    return out, err, code


if __name__ == "__main__":
    if not HOST or not PASS:
        sys.stderr.write("VPS_HOST and VPS_PASS env vars are required\n")
        sys.exit(2)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "echo hello"
    to = int(sys.argv[2]) if len(sys.argv) > 2 else 120
    o, e, code = run(cmd, to)
    sys.stdout.write(o)
    if e:
        sys.stderr.write(e)
    sys.exit(code)
