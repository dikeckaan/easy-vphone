#!/usr/bin/env python3
"""SSH only through an explicit usbmux UDID; never falls back to another device."""
import argparse
import re
import signal
import socket
import subprocess
import time


def ssh_args(udid, user, local_port, command=None):
    if not re.fullmatch(r'[A-Fa-f0-9-]{16,64}', udid):
        raise ValueError('Invalid VM UDID')
    if not re.fullmatch(r'[a-zA-Z0-9_][a-zA-Z0-9_-]*', user):
        raise ValueError('Invalid SSH user')
    args = ['/usr/bin/ssh', '-tt', '-o', 'ConnectTimeout=10',
            '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2',
            '-o', 'HostKeyAlias=easy-vphone-' + udid.lower(),
            '-o', 'CheckHostIP=no', '-p', str(local_port), user + '@127.0.0.1']
    if command:
        args.append(command)
    return args


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--udid', required=True)
    parser.add_argument('--user', default='mobile')
    parser.add_argument('--port', type=int, default=22222)
    parser.add_argument('--repair', action='store_true')
    args = parser.parse_args()
    ssh_args(args.udid, args.user, 1)  # Validate before launching anything.
    if not 1 <= args.port <= 65535:
        parser.error('Invalid guest SSH port')
    command = None
    if args.repair:
        command = ('if [ -x /cores/vpregister ]; then /cores/vpregister '
                   '/var/jb/Applications/Sileo.app /var/jb/Applications/TrollStoreLite.app; '
                   'elif [ -x /var/jb/usr/bin/uicache ]; then /var/jb/usr/bin/uicache -a; '
                   "else echo 'Jailbreak registration tool not found'; exit 1; fi")
    with socket.socket() as reservation:
        reservation.bind(('127.0.0.1', 0))
        port = reservation.getsockname()[1]
    proxy = subprocess.Popen(['/opt/homebrew/bin/iproxy', '-u', args.udid,
                              '-s', '127.0.0.1', f'{port}:{args.port}'])
    def stop(*_):
        raise SystemExit(130)
    signal.signal(signal.SIGTERM, stop)
    try:
        for _ in range(50):
            if proxy.poll() is not None:
                raise RuntimeError('VM proxy failed; SSH was not started')
            try:
                with socket.create_connection(('127.0.0.1', port), timeout=0.1):
                    pass
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise RuntimeError('VM proxy timed out')
        if proxy.poll() is not None:
            raise RuntimeError('VM proxy exited; SSH was not started')
        return subprocess.call(ssh_args(args.udid, args.user, port, command))
    finally:
        if proxy.poll() is None:
            proxy.terminate()
        try:
            proxy.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proxy.kill(); proxy.wait()

if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError) as exc:
        raise SystemExit(str(exc))
