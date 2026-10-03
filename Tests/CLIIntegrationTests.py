#!/usr/bin/env python3
"""Exercise the real CLI parser, framing, batch I/O and failure exits with a local fixture peer.
Production image operations are exercised by RegressionTests.swift, not by this peer.
No desktop capture, clipboard access, user settings, or external network is involved.
"""
import base64
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading

cli = Path(sys.argv[1])
passed = 0

def check(condition, label):
    global passed
    assert condition, label
    passed += 1
    print('PASS:', label, flush=True)

with tempfile.TemporaryDirectory(prefix='sc-cli-', dir='/private/tmp') as tmp:
    root = Path(tmp)
    endpoint = root / 'socket'
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(endpoint)); os.chmod(endpoint, 0o600); server.listen(4)
    requests = []
    errors = []

    def read_exact(peer, n):
        chunks = bytearray()
        while len(chunks) < n:
            chunk = peer.recv(n - len(chunks))
            if not chunk:
                raise EOFError()
            chunks.extend(chunk)
        return bytes(chunks)

    def serve():
        while True:
            try:
                peer, _ = server.accept()
            except OSError:
                return
            with peer:
                try:
                    length, = struct.unpack('>I', read_exact(peer, 4))
                    assert length <= 140_000_000
                    request = json.loads(read_exact(peer, length)); requests.append(request)
                    if request['command'] == 'process':
                        content = base64.b64decode(request['image'])
                        response = {'success': content != b'bad', 'message': 'invalid image' if content == b'bad' else '', 'image': request['image']}
                    else:
                        response = {'success': True, 'message': 'fixture ready'}
                    data = json.dumps(response).encode()
                    peer.sendall(struct.pack('>I', len(data)) + data)
                except Exception as exc:
                    errors.append(str(exc))

    thread = threading.Thread(target=serve, daemon=True); thread.start()

    def run(*args):
        return subprocess.run([str(cli), *map(str, args)], text=True, capture_output=True, timeout=15)

    check(run('--help').returncode == 0, 'CLI help works without a running App')
    check(run('unknown').returncode != 0, 'Unknown CLI commands return a failure exit')
    check(run('status', '--socket', endpoint).stdout.strip() == 'fixture ready', 'CLI uses the bounded local request/response protocol')
    input_a, input_b = root / 'a.png', root / 'b.png'
    input_a.write_bytes(b'image-a'); input_b.write_bytes(b'image-b')
    destination = root / 'result'; destination.mkdir()
    result = run('process', input_a, input_b, '--output-dir', destination, '--mosaic', '1,2,3,4', '--rotate', '90', '--socket', endpoint)
    check(result.returncode == 0 and (destination / 'a.png').read_bytes() == b'image-a' and (destination / 'b.png').read_bytes() == b'image-b', 'Batch writes one result per input in the requested folder')
    check(all(item.get('mosaic') == [[1, 2, 3, 4]] and item.get('rotation') == 90 for item in requests if item['command'] == 'process'), 'Batch image options are passed to every request')
    before = len(requests)
    check(run('process', input_a, '--output', destination / 'a.png', '--socket', endpoint).returncode != 0 and len(requests) == before, 'Existing output is rejected before contacting the App')
    check(run('process', input_a, '--output', destination / 'a.png', '--overwrite', '--socket', endpoint).returncode == 0, 'Explicit overwrite allows replacing an output')
    input_a.write_bytes(b'bad'); (destination / 'a.png').unlink(); (destination / 'b.png').unlink()
    result = run('process', input_a, input_b, '--output-dir', destination, '--socket', endpoint)
    check(result.returncode != 0 and not (destination / 'a.png').exists() and (destination / 'b.png').exists(), 'A failed batch item does not stop later items or produce a false success exit')
    duplicate = root / 'other'; duplicate.mkdir(); (duplicate / 'b.png').write_bytes(b'other')
    before = len(requests)
    check(run('process', input_b, duplicate / 'b.png', '--output-dir', destination, '--overwrite', '--socket', endpoint).returncode != 0 and len(requests) == before, 'Batch detects duplicate output names before work starts')
    check(run('process', input_b, '--region', '1,two,3,4', '--output', root / 'invalid.png', '--socket', endpoint).returncode != 0, 'Malformed region arguments are rejected')
    check(not errors, 'Fixture peer observed no framing errors')
    server.close()
print(f'{passed} CLI integration checks passed.')
