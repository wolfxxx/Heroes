"""Run Python in the live Blender through the MCP addon's socket (port 9876), without the MCP server.
python tools/art/blender/bl.py script.py [--timeout S]     or     python tools/art/blender/bl.py -c "code"
Prints what the code printed. Useful for long jobs: the MCP tool gives up after ~2 min, this waits."""
import socket, json, sys, argparse

def run(code, timeout=1800, port=9876):
    s = socket.create_connection(("localhost", port), timeout=timeout)
    s.sendall(json.dumps({"type": "execute_code", "params": {"code": code}}).encode())
    buf = b""
    while True:
        chunk = s.recv(65536)
        if not chunk:
            break
        buf += chunk
        try:
            return json.loads(buf)
        except ValueError:
            continue
    return json.loads(buf) if buf else None

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("script", nargs="?")
    ap.add_argument("-c", dest="code")
    ap.add_argument("--timeout", type=float, default=1800)
    a = ap.parse_args()
    r = run(a.code if a.code else open(a.script, encoding="utf-8").read(), a.timeout)
    if r and r.get("status") == "success":
        print(r["result"].get("result", ""), end="")
    else:
        print(r)
        sys.exit(1)
