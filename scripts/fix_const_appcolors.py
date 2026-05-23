"""Bulk remove `const ` prefix from widget constructors that contain AppColors dynamic getters.

Reason: AppColors.{background,surface,textPrimary,...} are now static getters (not const),
so widgets like `const Text(style: TextStyle(color: AppColors.textPrimary))` fail to compile.

Algorithm:
1. Scan each .dart file char-by-char.
2. Match pattern `const  <CapitalIdent>(`.
3. Walk forward with balanced paren tracking to find matching `)`.
4. Inside scope, search for `AppColors.<dynamic_name>` regex.
5. If found, remove the `const ` keyword.
6. Repeat until no changes (handles nested const).
"""
import re
import glob
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

DYNAMIC = {
    "background",
    "surface",
    "surfaceLight",
    "surfaceCard",
    "textPrimary",
    "textSecondary",
    "textTertiary",
    "divider",
    "border",
    "chatBubbleAi",
    "chatBubbleUser",
    "backgroundGradient",
}
DYN_PATTERN = re.compile(r"AppColors\.(" + "|".join(DYNAMIC) + r")\b")
CONST_WIDGET_PATTERN = re.compile(r"const(\s+)([A-Z][\w.]*(?:<[^>]+>)?)\(")


def find_removals(content):
    removals = []
    n = len(content)
    i = 0
    while i < n:
        m = CONST_WIDGET_PATTERN.match(content, i)
        if not m:
            i += 1
            continue
        space_after_const_len = len(m.group(1))
        paren_start = m.end() - 1  # at '('
        depth = 0
        scope_end = -1
        j = paren_start
        in_string = None
        prev = ""
        backslash = chr(92)  # backslash char
        while j < n:
            c = content[j]
            if in_string is not None:
                if c == in_string and prev != backslash:
                    in_string = None
            else:
                if c in ('"', "'"):
                    in_string = c
                elif c == "(":
                    depth += 1
                elif c == ")":
                    depth -= 1
                    if depth == 0:
                        scope_end = j + 1
                        break
            prev = c
            j += 1
        if scope_end < 0:
            i = paren_start + 1
            continue
        scope = content[paren_start:scope_end]
        if DYN_PATTERN.search(scope):
            removals.append((i, 5 + space_after_const_len))  # 'const' + spaces
        i = paren_start + 1
    return removals


def process_file(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    original = content
    iterations = 0
    while iterations < 5:  # safety bound
        rems = find_removals(content)
        if not rems:
            break
        rems.sort(key=lambda r: -r[0])
        for start, length in rems:
            content = content[:start] + content[start + length :]
        iterations += 1
    if content != original:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return len(original) - len(content)
    return 0


files = glob.glob("lib/**/*.dart", recursive=True)
total = 0
for f in files:
    delta = process_file(f)
    if delta > 0:
        approx_count = delta // 6
        print(f"  {f}: -{approx_count} const")
        total += approx_count
print(f"\nTotal const removed: {total}")
