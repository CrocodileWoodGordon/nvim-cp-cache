"""Standard-library HTTP fixture client; called asynchronously by Neovim tests."""
import json
import socket
import sys
import time

request = json.load(sys.stdin)
body = request.get("body", "").encode("utf-8")
method = request.get("method", "POST")
headers = request.get("headers", f"Content-Length: {len(body)}\r\nContent-Type: application/json\r\n")
wire = (f"{method} / HTTP/1.1\r\nHost: localhost\r\n" + headers + "\r\n").encode() + body
with socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=3) as connection:
    connection.settimeout(5)
    if request.get("idle"):
        connection.sendall(wire[:-1])
    elif request.get("fragments"):
        for offset in range(0, len(wire), 7):
            connection.sendall(wire[offset:offset + 7])
            time.sleep(0.001)
    else:
        connection.sendall(wire)
    response = bytearray()
    while True:
        chunk = connection.recv(65536)
        if not chunk:
            break
        response.extend(chunk)
head, _, data = response.partition(b"\r\n\r\n")
code = int(head.split(b" ")[1])
print(json.dumps({"code": code, "body": data.decode("utf-8")}))
