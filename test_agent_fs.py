#!/usr/bin/env python3
# host-side check of the two bits with real logic: newtask and the mount table

import importlib.util
import pathlib
import subprocess
import tempfile

HERE = pathlib.Path(__file__).parent


def load_watcher(data):
    spec = importlib.util.spec_from_file_location("watcher", HERE / "watcher.py")
    w = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(w)
    w.DATA = data
    w.AGENTS = data / "agents"
    w.SHARED = data / "shared"
    return w


def fake_data(root):
    for name in ("orchestrator", "code"):
        agent = root / "agents" / name
        (agent / "kanban/backlog").mkdir(parents=True)
        (agent / "home").mkdir(parents=True)
        (agent / "agent.yaml").write_text("agents: {}\n")
    (root / "shared/skills/kanban").mkdir(parents=True)
    (root / "shared/skills/kanban/SKILL.md").write_text("---\nname: kanban\n---\n")
    (root / "agents/code/skills/lint").mkdir(parents=True)
    (root / "agents/code/skills/lint/SKILL.md").write_text("---\nname: lint\n---\n")
    return root


def test_newtask():
    with tempfile.TemporaryDirectory() as tmp:
        out = subprocess.run(["sh", str(HERE / "seed/base/newtask"), tmp, "fix the parser"],
                             input="do the thing\n", text=True, capture_output=True,
                             env={"AGENT_NAME": "code", "PARENT": "task-1", "PATH": "/usr/bin:/bin"})
        assert out.returncode == 0, out.stderr
        task = pathlib.Path(out.stdout.strip())
        body = task.read_text()
        assert task.name.startswith("task-") and task.parent == pathlib.Path(tmp)
        assert "created_by: code" in body and "parent: task-1" in body
        assert "# fix the parser" in body and body.endswith("do the thing\n")
        assert not list(pathlib.Path(tmp).glob(".*.tmp")), "temp file left behind"


def test_mounts():
    with tempfile.TemporaryDirectory() as tmp:
        w = load_watcher(fake_data(pathlib.Path(tmp)))

        code = " ".join(w.mounts("code"))
        assert f"{tmp}/agents/code/soul.md:/agent/soul.md:ro" in code
        assert f"{tmp}/agents/code/kanban:/agent/kanban " in code + " "
        assert f"{tmp}/agents/code/kanban/backlog:/agent/kanban/backlog:ro" in code
        assert f"{tmp}/agents/orchestrator/kanban/backlog:/shared/requests" in code
        assert "/agent/home/.agents/skills/kanban:ro" in code, "shared skill missing"
        assert "/agent/home/.agents/skills/lint:ro" in code, "agent skill missing"
        assert "/data" not in code, "sub-agent must not see /data"
        assert f"{tmp}/agents/orchestrator/home" not in code, "sub-agent must not see another home"

        # parents mount before their children, else docker buries the child mount
        dests = [a.split(":")[1] for a in w.mounts("code") if a.startswith("/")]
        assert dests.index("/agent/kanban") < dests.index("/agent/kanban/backlog")

        orch = " ".join(w.mounts("orchestrator"))
        assert f"{tmp}:/data" in orch and "/shared/requests" not in orch


def test_env_is_scoped():
    with tempfile.TemporaryDirectory() as tmp:
        w = load_watcher(fake_data(pathlib.Path(tmp)))
        w.os.environ.update({"ANTHROPIC_API_KEY": "k", "MAIL_SMTP_PASS": "p", "CODE_TOKEN": "t"})
        code = w.env_args("code")
        assert "CODE_TOKEN=t" in code and "ANTHROPIC_API_KEY=k" in code
        assert "MAIL_SMTP_PASS=p" not in code
        assert "GIT_AUTHOR_NAME=orchestrator" in w.env_args("orchestrator")


if __name__ == "__main__":
    test_newtask()
    test_mounts()
    test_env_is_scoped()
    print("ok")
