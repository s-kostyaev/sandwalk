#!/usr/bin/env python3
"""Deterministic lock and watchdog checks for the SearXNG service helper."""

from __future__ import annotations

import fcntl
import importlib.machinery
import json
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def load(path: Path):
    return importlib.machinery.SourceFileLoader("sandwalk_searxng_service", str(path)).load_module()


def atomic_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value), encoding="utf-8")


def check_activity_lock(module, directory: Path) -> None:
    activity = directory / "activity.lock"
    ready = directory / "ready"
    child_source = """
import fcntl, os, sys, time
descriptor = os.open(sys.argv[1], os.O_RDWR | os.O_CREAT, 0o600)
fcntl.flock(descriptor, fcntl.LOCK_SH)
open(sys.argv[2], 'w').close()
time.sleep(0.4)
os.close(descriptor)
"""
    child = subprocess.Popen([sys.executable, "-c", child_source, str(activity), str(ready)])
    deadline = time.monotonic() + 2
    while not ready.exists() and time.monotonic() < deadline:
        time.sleep(0.01)
    assert ready.exists(), "shared-lock child did not start"
    started = time.monotonic()
    with module.lifecycle_locks(directory, activity=True):
        pass
    elapsed = time.monotonic() - started
    child.wait(timeout=2)
    assert elapsed >= 0.25, "exclusive lifecycle operation did not wait for active search"


def state(module, generation: int = 3) -> dict:
    return {
        "schema": module.STATE_SCHEMA,
        "mode": "managed",
        "container_id": "container-id",
        "container_name": "sandwalk-searxng-test",
        "endpoint": "http://127.0.0.1:18888",
        "image": module.PINNED_IMAGE,
        "image_digest": "sha256:" + "a" * 64,
        "profile": module.PROFILE,
        "language": "all",
        "safe_search": 0,
        "config_sha256": "b" * 64,
        "desired_sha256": "c" * 64,
        "generation": generation,
        "host_port": 18888,
        "idle_timeout_seconds": 1,
    }


def container(module) -> dict:
    return {
        "Id": "container-id",
        "Image": "sha256:" + "a" * 64,
        "State": {"Running": True, "Status": "running"},
        "Config": {
            "Labels": {
                "io.sandwalk.service": "searxng",
                "io.sandwalk.uid": str(module.os.getuid()),
                "io.sandwalk.config-sha256": "b" * 64,
            }
        },
    }


def check_watchdog(module, directory: Path) -> None:
    service_state = state(module)
    atomic_json(directory / "service.json", service_state)
    atomic_json(
        directory / "lease.json",
        {
            "schema": module.LEASE_SCHEMA,
            "generation": 3,
            "container_id": "container-id",
            "deadline_unix": time.time() - 1,
            "idle_timeout_seconds": 1,
        },
    )
    calls: list[tuple] = []
    module.verify_local_docker = lambda: None
    module.inspect_container = lambda _identifier: container(module)
    module.docker = lambda *arguments, **keywords: calls.append(arguments)
    assert module.watchdog(directory) == 0
    assert ("container", "stop", "container-id") in calls
    assert not (directory / "lease.json").exists()

    calls.clear()
    atomic_json(directory / "service.json", service_state)
    atomic_json(
        directory / "lease.json",
        {
            "schema": module.LEASE_SCHEMA,
            "generation": 2,
            "container_id": "container-id",
            "deadline_unix": time.time() - 1,
            "idle_timeout_seconds": 1,
        },
    )
    assert module.watchdog(directory) == 0
    assert not calls, "stale watchdog generation stopped the current container"


def check_curated_settings(module) -> None:
    config = {
        "engines": {
            "profile": module.PROFILE,
            "enable": [],
            "disable": ["brave"],
            "keep_only": None,
        },
        "search": {"language": "all", "safe_search": 0},
    }
    settings = module.generated_settings(config, "test-secret")
    assert "      - \"crossref\"" in settings
    assert "  - name: \"crossref\"\n    disabled: false" in settings
    assert "  - name: \"brave\"\n    disabled: true" in settings


def check_remote_docker_rejected(module) -> None:
    previous = module.os.environ.get("DOCKER_HOST")
    module.os.environ["DOCKER_HOST"] = "tcp://docker.example.test:2376"
    try:
        try:
            module.verify_local_docker()
        except module.ServiceError as error:
            assert "local Docker endpoint" in str(error)
        else:
            raise AssertionError("remote DOCKER_HOST was accepted")
    finally:
        if previous is None:
            module.os.environ.pop("DOCKER_HOST", None)
        else:
            module.os.environ["DOCKER_HOST"] = previous


def main() -> None:
    module = load(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="sandwalk-searxng-test-") as temporary:
        directory = Path(temporary)
        check_curated_settings(module)
        check_remote_docker_rejected(module)
        check_activity_lock(module, directory)
        check_watchdog(module, directory)
    print("searxng service locks and watchdog: ok")


if __name__ == "__main__":
    main()
