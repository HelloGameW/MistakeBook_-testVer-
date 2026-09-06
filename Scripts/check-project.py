"""Static checks only (not Swift type checking). Requires PyYAML and tree-sitter-swift."""
from pathlib import Path
import json
import os
import plistlib
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

import yaml
import tree_sitter_swift
from tree_sitter import Language, Parser

root = Path(__file__).resolve().parent.parent
parser = Parser(Language(tree_sitter_swift.language()))
errors = []
files = list(root.rglob("*.swift"))
for file in files:
    if "build" in file.relative_to(root).parts or ".build" in file.relative_to(root).parts:
        continue
    tree = parser.parse(file.read_bytes())
    if tree.root_node.has_error:
        pending = [tree.root_node]
        while pending:
            node = pending.pop()
            if node.type == "ERROR" or node.is_missing:
                errors.append(f"{file.relative_to(root)}:{node.start_point.row + 1}: {node.type}")
            pending.extend(reversed(node.children))
print(f"Swift syntax: {len(files)} files; {len(errors)} parser errors", flush=True)
for error in errors:
    print(error)

config = yaml.safe_load((root / "codemagic.yaml").read_text(encoding="utf-8"))
scripts = config["workflows"]["mistakebook-ios-device"]["scripts"]
bash = os.environ.get("BASH_PATH") or shutil.which("bash")
assert bash, "bash is required for shell syntax checks"
for name, source in [(step["name"], step["script"]) for step in scripts] + [
    (file.name, file.read_text(encoding="utf-8")) for file in (root / "Scripts").glob("*.sh")
]:
    result = subprocess.run([bash, "-n"], input=source, text=True, encoding="utf-8", capture_output=True)
    assert result.returncode == 0, (name, result.stderr)
print(f"YAML and shell syntax: PASS; {len(scripts)} CI steps", flush=True)
for file in list((root / "MistakeBook").glob("*.plist")) + list((root / "MistakeBook").glob("*.xcprivacy")):
    plistlib.loads(file.read_bytes())
for file in (root / "MistakeBook.xcodeproj").rglob("*.xcscheme"):
    ET.parse(file)
for directory in ["Resources", "Tests", "Packages/MistakeKit/Tests"]:
    for file in (root / directory).rglob("*.json"):
        json.loads(file.read_text(encoding="utf-8-sig"))
print("Plist, privacy manifest, scheme XML and JSON: PASS", flush=True)
project = (root / "MistakeBook.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
for path in re.findall(r'"path" = "([^"]+)";', project):
    if not path.endswith((".app", ".xctest")):
        assert (root / path).exists(), path
ids = re.findall(r'^\t\t"([A-F0-9]{24})" = \{', project, re.M)
assert len(ids) == len(set(ids)), "Duplicate Xcode object IDs"
assert set(re.findall(r'"([A-F0-9]{24})"', project)) <= set(ids), "Dangling Xcode reference"
for file in (root / "Packages/MistakeKit/Tests").rglob("*.swift"):
    assert f'"path" = "{file.relative_to(root).as_posix()}";' in project, file
for file in (root / "Packages/MistakeKit/Tests/ContractsTests/Fixtures").glob("*.json"):
    assert file.read_bytes() == (root / "Tests/Fixtures" / file.name).read_bytes(), file
print("Xcode references, test file references and fixture parity: PASS", flush=True)
assert not errors, "Swift parser found syntax errors; inspect them with Xcode"
