#!/usr/bin/env python3
"""Real localhost Icecast/SHOUTcast and FFmpeg RTMP receivers; no external streams."""
import array
import contextlib
import math
import os
from pathlib import Path
import socket
import ssl
import subprocess
import threading
import time
import urllib.request
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "Build" / "BroadcastValidation"
WORK.mkdir(parents=True, exist_ok=True)
FFMPEG = "/opt/homebrew/bin/ffmpeg"
ICECAST = "/opt/homebrew/bin/icecast"
CLIENT = str(ROOT / "Build" / "BroadcastIntegration")
checks = 0


def check(condition, message):
    global checks
    print(f'{"PASS" if condition else "FAIL"} {message}', flush=True)
    if not condition:
        raise AssertionError(message)
    checks += 1


def port_pair():
    for _ in range(100):
        with socket.socket() as first, socket.socket() as second:
            first.bind(("127.0.0.1", 0))
            port = first.getsockname()[1]
            try:
                second.bind(("127.0.0.1", port + 1))
                return port
            except OSError:
                pass
    raise RuntimeError("No localhost test ports available")


def finish(process, timeout=20):
    try:
        return process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill()
        process.communicate()
        raise


def icecast_ports():
    port, tls = port_pair(), port_pair()
    while tls in (port, port + 1):
        tls = port_pair()
    return port, tls


def client(mode, endpoint, codec="mp3", duration=8, ca=False, executable=None):
    env = dict(os.environ)
    if ca:
        env["NOIR_TEST_CA"] = str(WORK / "certificate.pem")
    else:
        env.pop("NOIR_TEST_CA", None)
    if executable:
        env["NOIR_TEST_ENCODER"] = str(executable)
    return subprocess.Popen([CLIENT, mode, endpoint, codec, str(duration)], cwd=ROOT, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)


def verify_client(process):
    output, _ = finish(process)
    print(output, end="", flush=True)
    check(process.returncode == 0, "Broadcast client assertions passed")


def verify_audio(raw, name):
    samples = array.array("f")
    samples.frombytes(raw[:len(raw) // 8 * 8])
    finite = all(math.isfinite(x) for x in samples)
    peak = max(map(abs, samples), default=0)
    rms = math.sqrt(sum(x*x for x in samples) / max(1, len(samples)))
    left = samples[::2]
    left = left[len(left)//4:len(left)*3//4] # Exclude encoder priming and end padding.
    crossings, armed = 0, False
    for value in left:
        if value < -0.02:
            armed = True
        elif value > 0.02 and armed:
            crossings += 1
            armed = False
    hz = crossings * 48000 / max(1, len(left))
    check(finite and len(samples) >= 180000 and 0.07 < peak < 0.15 and rms > 0.04 and abs(hz - 440) < 5,
          f"{name}: separate listener decodes stereo 48 kHz audio, {hz:.1f} Hz, peak {peak:.3f}")


def await_mount(url):
    deadline = time.monotonic() + 7
    while time.monotonic() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=0.5) as response:
                if response.status == 200:
                    return
        except Exception:
            time.sleep(0.1)
    raise RuntimeError(f"Local mount did not become available: {url}")


@contextlib.contextmanager
def icecast(port, tls_port):
    config = WORK / "icecast.xml"
    config.write_text(f'''<icecast>
      <location>Local validation</location><admin>test@localhost</admin><hostname>localhost</hostname>
      <limits><clients>20</clients><sources>10</sources><queue-size>524288</queue-size><burst-size>65535</burst-size></limits>
      <authentication><source-password>noir-test-password</source-password><relay-password>noir-test-password</relay-password><admin-user>admin</admin-user><admin-password>noir-test-password</admin-password></authentication>
      <listen-socket><port>{port}</port><bind-address>127.0.0.1</bind-address><shoutcast-mount>/legacy.mp3</shoutcast-mount></listen-socket>
      <listen-socket><port>{tls_port}</port><bind-address>127.0.0.1</bind-address><ssl>1</ssl></listen-socket>
      <paths><basedir>{escape(str(WORK))}</basedir><logdir>{escape(str(WORK))}</logdir>
      <webroot>/opt/homebrew/share/icecast/web</webroot><adminroot>/opt/homebrew/share/icecast/admin</adminroot>
      <ssl-certificate>{escape(str(WORK / "server.pem"))}</ssl-certificate></paths>
      <logging><accesslog>access.log</accesslog><errorlog>error.log</errorlog><loglevel>2</loglevel></logging>
      <security><chroot>0</chroot></security></icecast>''')
    with (WORK / "icecast-process.log").open("w") as log:
        process = subprocess.Popen([ICECAST, "-c", str(config)], stdout=log, stderr=log)
        try:
            time.sleep(0.4)
            check(process.poll() is None, "Isolated Icecast server starts on localhost")
            yield process
        finally:
            if process.poll() is None:
                process.terminate()
            process.wait(timeout=5)


def stream_case(name, endpoint, mount, port, codec="mp3", ca=False):
    sender = client(name, endpoint, codec, ca=ca)
    try:
        url = f"http://127.0.0.1:{port}{mount}"
        try:
            await_mount(url)
        except Exception:
            output, _ = finish(sender)
            print(output, end="", flush=True)
            raise
        receiver = subprocess.run([FFMPEG, "-v", "error", "-rw_timeout", "5000000", "-i", url,
                                   "-t", "2", "-ar", "48000", "-ac", "2", "-f", "f32le", "pipe:1"],
                                  capture_output=True, timeout=10)
        (WORK / f"{name}.f32").write_bytes(receiver.stdout)
        check(receiver.returncode == 0, f"{name}: listener accepts the stream")
        verify_audio(receiver.stdout, name)
        verify_client(sender)
    finally:
        if sender.poll() is None:
            sender.kill(); sender.wait()


@contextlib.contextmanager
def tls_proxy(upstream):
    # FFmpeg has an RTMP listener, but intentionally has no RTMPS listener.
    # Terminate real TLS locally and forward the decrypted protocol to it.
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(WORK / "certificate.pem", WORK / "key.pem")
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0)); listener.listen(1); listener.settimeout(15)
    connections = []
    def forward(source, target):
        try:
            while True:
                data = source.recv(8192)
                if not data:
                    break
                target.sendall(data)
        except (OSError, ssl.SSLError):
            pass
        finally:
            for item in (source, target):
                try: item.shutdown(socket.SHUT_RDWR)
                except OSError: pass
    def serve():
        try:
            plain, _ = listener.accept(); connections.append(plain)
            secured = context.wrap_socket(plain, server_side=True)
            backend = socket.create_connection(("127.0.0.1", upstream), timeout=15)
            connections.extend([secured, backend])
            threading.Thread(target=forward, args=(backend, secured), daemon=True).start()
            forward(secured, backend)
        except (OSError, ssl.SSLError):
            pass
    threading.Thread(target=serve, daemon=True).start()
    try:
        yield listener.getsockname()[1]
    finally:
        listener.close()
        for item in connections:
            item.close()


def rtmp_case(secure=False):
    port = port_pair()
    scheme = "rtmps" if secure else "rtmp"
    endpoint = f"rtmp://127.0.0.1:{port}/live/noir"
    target = WORK / f"{scheme}.f32"
    args = [FFMPEG, "-y", "-v", "error", "-listen", "1", "-rw_timeout", "15000000"]
    args += ["-i", endpoint, "-ar", "48000", "-ac", "2", "-f", "f32le", str(target)]
    receiver = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        time.sleep(0.4)
        with tls_proxy(port) if secure else contextlib.nullcontext(port) as source_port:
            sender = client(scheme, f"{scheme}://127.0.0.1:{source_port}/live/noir", "aac", ca=secure)
            verify_client(sender)
        finish(receiver)
        verify_audio(target.read_bytes(), scheme)
    finally:
        if receiver.poll() is None:
            receiver.kill(); receiver.wait()


def certificate(hostname="localhost"):
    alternative = "DNS:localhost,IP:127.0.0.1" if hostname == "localhost" else f"DNS:{hostname}"
    subprocess.run(["/opt/homebrew/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-noenc", "-days", "1",
                    "-subj", f"/CN={hostname}", "-addext", f"subjectAltName={alternative}",
                    "-keyout", str(WORK / "key.pem"), "-out", str(WORK / "certificate.pem")], check=True, capture_output=True)
    (WORK / "key.pem").chmod(0o600)
    (WORK / "server.pem").write_bytes((WORK / "certificate.pem").read_bytes() + (WORK / "key.pem").read_bytes())
    (WORK / "server.pem").chmod(0o600)


def reconnect_after_disconnect():
    port, tls = icecast_ports()
    sender = None
    try:
        with icecast(port, tls):
            sender = client("reconnect", f"icecast://127.0.0.1:{port}/restart.mp3", duration=18)
            await_mount(f"http://127.0.0.1:{port}/restart.mp3")
            time.sleep(2)
        time.sleep(1)
        with icecast(port, tls):
            await_mount(f"http://127.0.0.1:{port}/restart.mp3")
            check(True, "Established stream reconnects after the actual server is terminated and restarted")
            receiver = subprocess.run([FFMPEG, "-v", "error", "-i", f"http://127.0.0.1:{port}/restart.mp3", "-t", "2", "-f", "f32le", "pipe:1"], capture_output=True, timeout=10)
            verify_audio(receiver.stdout, "reconnected-icecast")
            verify_client(sender)
    finally:
        if sender is not None and sender.poll() is None:
            sender.kill(); sender.wait()


def main():
    certificate()
    port, tls = icecast_ports()
    with icecast(port, tls):
        for codec, extension in [("mp3", "mp3"), ("aac", "aac"), ("opus", "ogg")]:
            mount = f"/test.{extension}"
            stream_case(f"icecast-{codec}", f"icecast://127.0.0.1:{port}{mount}", mount, port, codec)
        stream_case("shoutcast", f"shoutcast://127.0.0.1:{port+1}", "/legacy.mp3", port)
        stream_case("icecast-tls", f"icecasts://127.0.0.1:{tls}/secure.mp3", "/secure.mp3", port, ca=True)
        verify_client(client("bad-auth", f"icecast://127.0.0.1:{port}/rejected.mp3", duration=4))
        verify_client(client("bad-auth", f"shoutcast://127.0.0.1:{port+1}", duration=4))
        verify_client(client("untrusted-tls", f"icecasts://127.0.0.1:{tls}/untrusted.mp3", duration=4))
        # A stream starts before its server; the real source must reconnect once it appears.
        delayed_port, delayed_tls = icecast_ports()
        sender = client("reconnect", f"icecast://127.0.0.1:{delayed_port}/retry.mp3", duration=12)
        time.sleep(2)
        with icecast(delayed_port, delayed_tls):
            await_mount(f"http://127.0.0.1:{delayed_port}/retry.mp3")
            verify_client(sender)
    rtmp_case(); rtmp_case(secure=True)
    reconnect_after_disconnect()
    certificate("wrong.example.invalid")
    port, tls = icecast_ports()
    with icecast(port, tls):
        verify_client(client("wrong-hostname", f"icecasts://127.0.0.1:{tls}/rejected.mp3", duration=4, ca=True))
    stalled = WORK / "stalled-encoder"
    stalled.write_text("#!/usr/bin/env python3\nimport time\ntime.sleep(30)\n")
    stalled.chmod(0o755)
    verify_client(client("stalled", "icecast://127.0.0.1:9/stall.mp3", duration=5, executable=stalled))
    print(f"RESULT {checks} receiver/server checks passed; no external endpoints used", flush=True)


if __name__ == "__main__":
    main()
