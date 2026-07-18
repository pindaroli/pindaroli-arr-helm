#!/usr/bin/env python3
import os
import sys

def preprocess_cue(cue_path):
    dirname = os.path.dirname(cue_path)
    if not os.path.exists(dirname):
        return

    # Convert encoding from ISO-8859-1/Windows-1252 to UTF-8 if needed
    try:
        with open(cue_path, "rb") as f:
            raw = f.read()
    except Exception as e:
        print(f"Error reading file: {e}", file=sys.stderr)
        return

    try:
        content = raw.decode("utf-8")
    except UnicodeDecodeError:
        try:
            content = raw.decode("latin1", errors="replace")
            with open(cue_path, "w", encoding="utf-8") as f:
                f.write(content)
        except Exception as e:
            print(f"Error converting encoding: {e}", file=sys.stderr)

    try:
        files_in_dir = {f.lower(): f for f in os.listdir(dirname)}
    except Exception as e:
        print(f"Error listing directory: {e}", file=sys.stderr)
        return

    try:
        with open(cue_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Error reading lines: {e}", file=sys.stderr)
        return

    new_lines = []
    modified = False
    for line in lines:
        if line.strip().startswith("FILE "):
            parts = line.split("\"")
            if len(parts) >= 3:
                filename = parts[1]
                if not os.path.exists(os.path.join(dirname, filename)):
                    lower_name = filename.lower()
                    if lower_name in files_in_dir:
                        parts[1] = files_in_dir[lower_name]
                        line = "\"".join(parts)
                        modified = True
                    else:
                        prefix = filename.split()[0] if filename else ""
                        if prefix:
                            for f_lower, f_exact in files_in_dir.items():
                                if f_lower.startswith(prefix.lower()):
                                    parts[1] = f_exact
                                    line = "\"".join(parts)
                                    modified = True
                                    break
        new_lines.append(line)

    if modified:
        try:
            with open(cue_path, "w", encoding="utf-8") as f:
                f.writelines(new_lines)
        except Exception as e:
            print(f"Error writing file: {e}", file=sys.stderr)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: preprocess_cue.py <cue_file>", file=sys.stderr)
        sys.exit(1)
    preprocess_cue(sys.argv[1])
