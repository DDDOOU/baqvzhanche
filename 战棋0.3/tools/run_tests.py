"""Run the Godot smoke suite and reject silent script errors.

Usage: python tools/run_tests.py [path-to-godot-console]
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import sys


PROJECT_DIR = Path(__file__).resolve().parents[1]
WORKSPACE_DIR = Path(__file__).resolve().parents[3]


def find_godot() -> Path:
    if len(sys.argv) > 1:
        return Path(sys.argv[1]).resolve()
    from_path = shutil.which("godot") or shutil.which("godot4")
    if from_path:
        return Path(from_path)
    bundled = sorted(
        (WORKSPACE_DIR / ".tools").glob("godot-*/Godot_*_console.exe"),
        reverse=True,
    )
    if bundled:
        return bundled[0]
    raise FileNotFoundError("未找到 Godot；请把控制台版可执行文件路径作为第一个参数传入。")


def main() -> int:
    godot = find_godot()
    env = os.environ.copy()
    user_root = WORKSPACE_DIR / ".godot-user"
    env.update(
        APPDATA=str(user_root / "Roaming"),
        LOCALAPPDATA=str(user_root / "Local"),
        TEMP=str(user_root / "Temp"),
        TMP=str(user_root / "Temp"),
    )
    (user_root / "Temp").mkdir(parents=True, exist_ok=True)
    suites = (
        ("res://tests/smoke_test.tscn", "[SMOKE TEST] PASS"),
        ("res://tests/level_02_smoke_test.tscn", "[LEVEL 02 TEST] PASS"),
        ("res://tests/campaign_framework_test.tscn", "[CAMPAIGN FRAMEWORK TEST] PASS"),
    )
    for scene, pass_marker in suites:
        result = subprocess.run(
            [str(godot), "--headless", "--path", str(PROJECT_DIR), scene],
            cwd=PROJECT_DIR,
            env=env,
            text=True,
            encoding="utf-8",
            errors="replace",
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        print(result.stdout, end="")
        bad_markers = ("SCRIPT ERROR", "[SMOKE TEST] FAIL", "[LEVEL 02 TEST] FAIL", "[CAMPAIGN FRAMEWORK TEST] FAIL")
        if result.returncode != 0 or pass_marker not in result.stdout or any(x in result.stdout for x in bad_markers):
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
