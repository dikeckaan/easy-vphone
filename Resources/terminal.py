#!/usr/bin/env python3
"""Private PTY bridge. Credentials travel only over stdin, never argv or disk."""
import os
import pty
import select
import signal
import sys
import termios
import struct
import fcntl


def main():
    if len(sys.argv) < 2:
        return 2
    pid, master = pty.fork()
    if pid == 0:
        settings = termios.tcgetattr(0)
        settings[3] &= ~termios.ECHO
        termios.tcsetattr(0, termios.TCSANOW, settings)
        os.environ['TERM'] = 'dumb'
        os.execvpe(sys.argv[1], sys.argv[1:], os.environ)
    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 120, 0, 0))
    def stop(*_):
        try:
            os.killpg(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        while True:
            ready, _, _ = select.select([master, 0], [], [])
            if master in ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                os.write(1, data)
            if 0 in ready:
                data = os.read(0, 4096)
                if not data:
                    stop()
                    break
                os.write(master, data)
    finally:
        os.close(master)
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status)

if __name__ == '__main__':
    sys.exit(main())
