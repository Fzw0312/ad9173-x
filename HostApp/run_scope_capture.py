import os
import sys
from pathlib import Path


def _restart_inside_local_venv() -> None:
    root = Path(__file__).resolve().parent
    venv_python = root / ".venv" / "Scripts" / "python.exe"
    if not venv_python.exists():
        return

    current_python = Path(sys.executable).resolve()
    if current_python == venv_python.resolve():
        return

    os.execv(str(venv_python), [str(venv_python), *sys.argv])


if __name__ == "__main__":
    _restart_inside_local_venv()
    from host_app.scope_capture_app import main

    main()
