#!/usr/bin/env python3
import os
import sys
import re

try:
    from mutagen.flac import FLAC
except ImportError:
    print("⚠️ mutagen not installed, skipping tag injection")
    sys.exit(0)

def tag_directory(target_dir):
    pattern = re.compile(r'\[Disc (\d+)\] - (\d+) - Track', re.IGNORECASE)
    # Fallback pattern for single CD or other naming
    pattern_fallback = re.compile(r'^(\d+) - Track', re.IGNORECASE)

    for root, dirs, files in os.walk(target_dir):
        for f in files:
            if f.endswith('.flac'):
                fpath = os.path.join(root, f)
                disc = None
                track = None
                
                m = pattern.search(f)
                if m:
                    disc = m.group(1)
                    track = str(int(m.group(2)))
                else:
                    m2 = pattern_fallback.search(f)
                    if m2:
                        disc = "1"
                        track = str(int(m2.group(1)))

                if track:
                    try:
                        audio = FLAC(fpath)
                        if disc:
                            audio["DISCNUMBER"] = disc
                        audio["TRACKNUMBER"] = track
                        audio.save()
                        print(f"🏷️ Auto-tagged: {f} -> Disc {disc or 1}, Track {track}")
                    except Exception as e:
                        print(f"⚠️ Error tagging {f}: {e}")

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    tag_directory(target)
