#!/usr/bin/env python3
"""Re-serialize a String Catalog exactly the way Xcode does.

Xcode writes `.xcstrings` as JSON with sorted keys, two-space indentation and a space on both
sides of the colon (`"key" : value`). Any other serializer produces a whole-file diff, and Xcode
rewrites it back on the next edit — so edit the catalog in Xcode, or run this after a hand /
scripted edit so the diff stays additive.

Usage:
  ./scripts/format-xcstrings.py Sources/AIConversation/Resources/Localizable.xcstrings
  ./scripts/format-xcstrings.py --check <file>   # exit 1 if the file is not in Xcode format
"""
import json
import re
import sys


def xcode_dump(obj) -> str:
    text = json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=True)
    text = re.sub(r'^(\s*"(?:[^"\\]|\\.)*")\s*:\s', r"\1 : ", text, flags=re.M)
    return text + "\n"


def main(argv: list[str]) -> int:
    check = "--check" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__, file=sys.stderr)
        return 2
    status = 0
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            original = handle.read()
        formatted = xcode_dump(json.loads(original))
        if formatted == original:
            continue
        if check:
            print(f"{path}: not in Xcode format (run scripts/format-xcstrings.py)", file=sys.stderr)
            status = 1
            continue
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(formatted)
        print(f"{path}: reformatted")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
