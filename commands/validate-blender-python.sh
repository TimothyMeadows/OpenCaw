#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./commands/validate-blender-python.sh <script.py> --root <repo> [--allow-output <relative-path>]...

Parses a restricted Blender Python script without executing it. On success,
prints the exact validated script SHA-256. Live execution must use that exact
content after a repository-confined backup checkpoint.
EOF
}

[[ "${1:-}" != "-h" && "${1:-}" != "--help" ]] || { usage; exit 0; }
[[ $# -ge 1 ]] || { usage >&2; exit 1; }
script="$1"; shift
root=""
allow_outputs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 && -z "$root" ]] || { echo "--root requires one path." >&2; exit 1; }; root="$2"; shift 2 ;;
    --allow-output) [[ $# -ge 2 ]] || { echo "--allow-output requires a relative path." >&2; exit 1; }; allow_outputs+=("$2"); shift 2 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
[[ -n "$root" && -d "$root" && ! -L "$root" ]] || { echo "--root must be a non-symlink directory." >&2; exit 1; }
[[ -f "$script" && ! -L "$script" && "${script,,}" == *.py ]] || { echo "Script must be a regular non-symlink .py file." >&2; exit 1; }
root_abs="$(realpath "$root")"; script_abs="$(realpath "$script")"
case "$script_abs" in "$root_abs"/*) ;; *) echo "Script escapes repository root." >&2; exit 1 ;; esac
python_bin="$(command -v python3 2>/dev/null || command -v python 2>/dev/null || command -v python.exe 2>/dev/null || true)"
[[ -n "$python_bin" ]] || { echo "Python 3 is required to validate Blender scripts." >&2; exit 1; }
python_root="$root_abs"; python_script="$script_abs"
if [[ "$python_bin" == *.exe && -n "$(command -v wslpath 2>/dev/null || true)" ]]; then python_root="$(wslpath -w "$root_abs")"; python_script="$(wslpath -w "$script_abs")"; fi

"$python_bin" - "$python_script" "$python_root" "${allow_outputs[@]}" <<'PY'
import ast
import hashlib
import pathlib
import re
import sys

script_path = pathlib.Path(sys.argv[1]).resolve(strict=True)
root = pathlib.Path(sys.argv[2]).resolve(strict=True)
raw_outputs = sys.argv[3:]
errors = []

def normalize_relative(value, where):
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value:
        errors.append(f"{where} must be a normalized repository-relative path")
        return None
    pure = pathlib.PurePosixPath(value)
    if pure.is_absolute() or re.match(r"^[A-Za-z]:", value) or any(part in {"", ".", ".."} for part in pure.parts):
        errors.append(f"{where} must be a normalized repository-relative path")
        return None
    candidate = (root / pathlib.Path(*pure.parts)).resolve(strict=False)
    try:
        candidate.relative_to(root)
    except ValueError:
        errors.append(f"{where} escapes repository root")
        return None
    return pure.as_posix()

allow_outputs = set()
for value in raw_outputs:
    normalized = normalize_relative(value, "--allow-output")
    if normalized:
        allow_outputs.add(normalized)

try:
    source = script_path.read_bytes()
    tree = ast.parse(source, filename=str(script_path))
except (OSError, SyntaxError) as error:
    print(f"Blender Python validation failed: {error}", file=sys.stderr)
    raise SystemExit(1)

allowed_modules = {"bpy", "bmesh", "math", "mathutils", "json", "hashlib", "pathlib"}
banned_calls = {"exec", "eval", "compile", "__import__", "breakpoint", "input", "globals", "locals", "vars", "getattr", "setattr", "delattr", "as_module", "run_script"}
banned_segments = {"subprocess", "socket", "requests", "urllib", "http", "ftplib", "paramiko", "multiprocessing", "ctypes", "importlib", "pkgutil", "pip", "ensurepip", "webbrowser", "secrets", "keyring"}
banned_terminals = {"unlink", "rmdir", "rename", "replace", "system", "popen", "spawn", "run_path", "run_module"}

def dotted(node):
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
        return ".".join(reversed(parts))
    return ""

def literal_path(node):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Call) and dotted(node.func) in {"Path", "pathlib.Path", "PurePath", "pathlib.PurePath"} and len(node.args) == 1 and not node.keywords:
        return literal_path(node.args[0])
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Div):
        left = literal_path(node.left)
        right = literal_path(node.right)
        if left is not None and right is not None:
            return pathlib.PurePosixPath(left, right).as_posix()
    return None

def check_path_node(node, where, write=False):
    value = literal_path(node)
    if value is None:
        errors.append(f"line {getattr(node, 'lineno', '?')}: {where} requires a literal path")
        return None
    normalized = normalize_relative(value, f"line {getattr(node, 'lineno', '?')}: {where}")
    if normalized is None:
        return None
    if write and normalized not in allow_outputs:
        errors.append(f"line {getattr(node, 'lineno', '?')}: output path is not declared by --allow-output: {normalized}")
    if not write and not (root / pathlib.Path(*pathlib.PurePosixPath(normalized).parts)).is_file():
        errors.append(f"line {getattr(node, 'lineno', '?')}: input file does not exist inside the repository: {normalized}")
    return normalized

render_output_declared = False
for node in ast.walk(tree):
    if isinstance(node, ast.Name) and node.id in {"__builtins__", "__loader__", "__spec__"}:
        errors.append(f"line {node.lineno}: reflective runtime access is prohibited")
    if isinstance(node, (ast.Import, ast.ImportFrom)):
        names = [alias.name for alias in node.names] if isinstance(node, ast.Import) else [node.module or ""]
        for name in names:
            top = name.split(".")[0]
            if top not in allowed_modules:
                errors.append(f"line {node.lineno}: import is not allowed: {name}")
    if isinstance(node, ast.Attribute):
        name = dotted(node)
        parts = set(name.split("."))
        if parts & banned_segments:
            errors.append(f"line {node.lineno}: prohibited capability reference: {name}")
        if name.startswith("bpy.context.preferences") or name.startswith("bpy.context.user_preferences"):
            errors.append(f"line {node.lineno}: Blender preference access is prohibited")
        if name.startswith(("bpy.app.handlers", "bpy.app.timers", "bpy.app.driver_namespace")):
            errors.append(f"line {node.lineno}: deferred or injected execution is prohibited")
    if isinstance(node, (ast.Assign, ast.AnnAssign)):
        targets = node.targets if isinstance(node, ast.Assign) else [node.target]
        value = node.value
        for target in targets:
            target_name = dotted(target)
            if target_name == "bpy.context.scene.render.filepath":
                check_path_node(value, "render filepath", write=True)
                render_output_declared = True
            if target_name.startswith("bpy.context.preferences") or target_name.startswith("bpy.context.user_preferences"):
                errors.append(f"line {node.lineno}: Blender preference mutation is prohibited")
    if not isinstance(node, ast.Call):
        continue
    name = dotted(node.func)
    terminal = node.func.attr if isinstance(node.func, ast.Attribute) else (name.rsplit(".", 1)[-1] if name else "")
    if terminal in banned_calls or terminal in banned_terminals:
        errors.append(f"line {node.lineno}: prohibited call: {name or terminal}")
    if any(segment in banned_segments for segment in name.split(".")):
        errors.append(f"line {node.lineno}: prohibited capability call: {name}")
    lowered = name.lower()
    if any(token in lowered for token in ["addon_install", "addon_enable", "extension_install", "package_install", "pip_install", "script.python_file_run"]):
        errors.append(f"line {node.lineno}: installation or arbitrary script execution is prohibited")
    if name.startswith("bpy.ops.text.") or name == "bpy.data.texts.load":
        errors.append(f"line {node.lineno}: Blender text execution or loading is prohibited")
    if name == "open":
        if not node.args:
            errors.append(f"line {node.lineno}: open requires a literal repository path")
        else:
            mode = "r"
            if len(node.args) > 1 and isinstance(node.args[1], ast.Constant): mode = str(node.args[1].value)
            for keyword in node.keywords:
                if keyword.arg == "mode" and isinstance(keyword.value, ast.Constant): mode = str(keyword.value.value)
            check_path_node(node.args[0], "open", write=any(flag in mode for flag in "wax+"))
    if terminal in {"write_text", "write_bytes", "touch", "mkdir"}:
        receiver = node.func.value if isinstance(node.func, ast.Attribute) else None
        check_path_node(receiver, terminal, write=True)
    if terminal == "open" and name != "open":
        receiver = node.func.value if isinstance(node.func, ast.Attribute) else None
        mode = "r"
        if node.args and isinstance(node.args[0], ast.Constant): mode = str(node.args[0].value)
        check_path_node(receiver, "path open", write=any(flag in mode for flag in "wax+"))
    if name in {"bpy.data.images.load", "bpy.data.libraries.load", "bpy.data.sounds.load", "bpy.data.movieclips.load"}:
        if not node.args: errors.append(f"line {node.lineno}: library load requires a literal repository path")
        else: check_path_node(node.args[0], name, write=False)
    path_keywords = [keyword for keyword in node.keywords if keyword.arg in {"filepath", "directory", "filename"}]
    for keyword in path_keywords:
        is_write = name.startswith("bpy.ops.export") or name in {"bpy.ops.wm.save_as_mainfile", "bpy.ops.wm.save_mainfile"}
        check_path_node(keyword.value, f"{name}.{keyword.arg}", write=is_write)
    if name in {"bpy.ops.wm.open_mainfile", "bpy.ops.wm.revert_mainfile", "bpy.ops.wm.read_factory_settings", "bpy.ops.wm.read_homefile"}:
        errors.append(f"line {node.lineno}: replacing the connected working scene is prohibited")
    if name == "bpy.ops.render.render":
        writes = any(keyword.arg in {"write_still", "animation"} and isinstance(keyword.value, ast.Constant) and bool(keyword.value.value) for keyword in node.keywords)
        if writes and not render_output_declared:
            errors.append(f"line {node.lineno}: render output requires a prior literal declared render filepath")

if errors:
    for error in sorted(set(errors)):
        print(f"- {error}", file=sys.stderr)
    raise SystemExit(1)

print(hashlib.sha256(source).hexdigest())
PY
