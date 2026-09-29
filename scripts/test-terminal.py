"""Check the complete package's daemon bootstrap on a real terminal."""
import fcntl
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

binary = str(Path(sys.argv[1]).resolve())
# macOS's default temporary path exceeds the Unix socket path limit.
with tempfile.TemporaryDirectory(prefix='codex-', dir='/tmp') as temporary:
    home = Path(temporary)
    env = dict(os.environ, HOME=temporary, CODEX_HOME=temporary, TERM='xterm-256color')
    (home / 'auth.json').write_text('{"OPENAI_API_KEY":"test-api-key"}\n')
    (home / 'config.toml').write_text(
        '[projects.' + json.dumps(temporary) + ']\ntrust_level = "trusted"\n')

    def daemon(*args):
        result = subprocess.run([binary, 'app-server', 'daemon', *args],
                              env=env, cwd=home, capture_output=True, text=True,
                              timeout=90)
        assert result.returncode == 0, result.stderr
        return result

    pid, fd = pty.fork()
    if pid == 0:
        os.chdir(home)
        os.execve(binary, [binary, '--no-alt-screen'], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    output = b''
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if select.select([fd], [], [], 1)[0]:
                try:
                    chunk = os.read(fd, 65536)
                except OSError:
                    chunk = b''
                assert chunk, output
                output += chunk
                if b'\x1b[6n' in chunk:
                    os.write(fd, b'\x1b[1;1R')
        for failure in [b'no complete local package', b'daemon executable not found']:
            assert failure not in output, output
        version = json.loads(daemon('version').stdout)
        assert version['status'] == 'running', version
        assert version['appServerVersion'] == version['cliVersion'], version
        print(version)
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
        os.close(fd)
        # Stop the updater too: daemon stop only stops the server.
        try:
            daemon('update', '--from-cli', '--yes')
        finally:
            daemon('stop')
