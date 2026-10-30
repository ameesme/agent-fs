#!/usr/bin/env python3
# starts agent containers when their todo/ fills up, rebuilds images when a Dockerfile changes

import hashlib
import http.server
import json
import os
import pathlib
import subprocess
import sys
import threading
import time

DATA = pathlib.Path("/data")
AGENTS = DATA / "agents"
SHARED = DATA / "shared"
STATE = DATA / ".build-state.json"
ORCH_TODO = AGENTS / "orchestrator/kanban/todo"
NEWTASK = DATA / "base/newtask"
POLL_SECONDS = 2


def log(*a):
    print(*a, flush=True)


def docker(*args, **kw):
    return subprocess.run(["docker", *args], text=True, capture_output=True, **kw)


def agent_names():
    return sorted(d.name for d in AGENTS.iterdir() if (d / "agent.yaml").is_file())


def tasks_waiting(name):
    todo = AGENTS / name / "kanban/todo"
    return any(p.name[0] != "." for p in todo.glob("*.md"))


def running():
    out = docker("ps", "--format", "{{.Names}}").stdout.split()
    return {n[len("agent-"):] for n in out if n.startswith("agent-")}


def dir_hash(path):
    h = hashlib.sha256()
    for f in sorted(p for p in path.rglob("*") if p.is_file()):
        h.update(str(f.relative_to(path)).encode())
        h.update(f.read_bytes())
    return h.hexdigest()


def build_images():
    state = json.loads(STATE.read_text()) if STATE.exists() else {}
    base = dir_hash(DATA / "base")

    if state.get("agent-base") != base:
        log("building agent-base")
        r = docker("build", "-t", "agent-base", str(DATA / "base"))
        if r.returncode:
            log(r.stderr.strip()[-2000:])
            return
        state["agent-base"] = base
        STATE.write_text(json.dumps(state))

    for name in agent_names():
        dockerfile = AGENTS / name / "Dockerfile"
        if not dockerfile.is_file():
            continue
        want = hashlib.sha256(dockerfile.read_bytes() + base.encode()).hexdigest()
        if state.get(name) == want:
            continue
        log(f"building agent-{name}")
        r = docker("build", "-t", f"agent-{name}", "-", input=dockerfile.read_text())
        if r.returncode:
            log(r.stderr.strip()[-2000:])
            continue
        state[name] = want
        STATE.write_text(json.dumps(state))
        fix_owner(name)


def fix_owner(name):
    uid = docker("image", "inspect", "-f", "{{.Config.User}}", f"agent-{name}").stdout.strip()
    uid = uid or "0"
    for sub in ("home", "kanban"):
        path = AGENTS / name / sub
        if path.stat().st_uid != int(uid):
            subprocess.run(["chown", "-R", f"{uid}:{uid}", str(path)])


def skill_mounts(name):
    found = {}
    for src in sorted(SHARED.glob("skills/*")) + sorted((AGENTS / name).glob("skills/*")):
        if (src / "SKILL.md").is_file():
            found[f"/agent/home/.agents/skills/{src.name}"] = (str(src), True)
    return found


def mounts(name):
    agent = AGENTS / name
    m = {
        "/agent/soul.md": (f"{agent}/soul.md", True),
        "/agent/agent.yaml": (f"{agent}/agent.yaml", True),
        "/agent/home": (f"{agent}/home", False),
        "/agent/kanban": (f"{agent}/kanban", False),
    }
    if name == "orchestrator":
        m["/data"] = (str(DATA), False)
    else:
        m["/agent/kanban/backlog"] = (f"{agent}/kanban/backlog", True)
        m["/shared/files"] = (f"{SHARED}/files", False)
        m["/shared/skills-proposed"] = (f"{SHARED}/skills-proposed", False)
        m["/shared/requests"] = (f"{AGENTS}/orchestrator/kanban/backlog", False)
    m.update(skill_mounts(name))
    args = []
    for dest in sorted(m, key=len):
        src, ro = m[dest]
        args += ["-v", f"{src}:{dest}:ro" if ro else f"{src}:{dest}"]
    return args


def env_args(name):
    args = ["-e", f"AGENT_NAME={name}"]
    prefix = name.upper().replace("-", "_") + "_"
    for key, value in os.environ.items():
        if key == "ANTHROPIC_API_KEY" or key.startswith(prefix):
            args += ["-e", f"{key}={value}"]
    if name == "orchestrator":
        for var in ("GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"):
            args += ["-e", f"{var}=orchestrator"]
        for var in ("GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"):
            args += ["-e", f"{var}=orchestrator@agent-fs.local"]
    return args


def start(name):
    log(f"starting agent-{name}")
    fix_owner(name)
    docker("rm", "-f", f"agent-{name}")
    r = docker("run", "-d", "--name", f"agent-{name}", *env_args(name), *mounts(name), f"agent-{name}")
    if r.returncode:
        log(r.stderr.strip())


def write_task(directory, title, body):
    r = subprocess.run(["sh", str(NEWTASK), str(directory), title], input=body,
                       text=True, capture_output=True, env={**os.environ, "AGENT_NAME": "watcher"})
    if r.returncode:
        log("newtask failed:", r.stderr.strip())
        return None
    return r.stdout.strip()


def review_task(name):
    body = (f"Agent `{name}` just finished its queue. Read the newest files in "
            f"/data/agents/{name}/kanban/done/ and /data/agents/{name}/kanban/blocked/, follow up on "
            f"anything blocked, and commit the definition and memory changes with the task id.")
    write_task(ORCH_TODO, f"review results of {name}", body)


class Endpoint(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length") or 0)).decode()
        title = self.headers.get("x-task-title") or body.strip().split("\n")[0][:60] or "task"
        path = write_task(ORCH_TODO, title, body)
        self.send_response(201 if path else 500)
        self.end_headers()
        self.wfile.write(f"{path}\n".encode())

    def log_message(self, *a):
        pass


def serve():
    http.server.ThreadingHTTPServer(("", 8080), Endpoint).serve_forever()


def main():
    threading.Thread(target=serve, daemon=True).start()
    log("watcher up, endpoint on :8080")
    build_images()
    was_running = set()
    while True:
        build_images()
        now = running()
        for name in was_running - now - {"orchestrator"}:
            review_task(name)
        for name in agent_names():
            if name not in now and tasks_waiting(name):
                start(name)
                now.add(name)
        was_running = now
        time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    sys.exit(main())
