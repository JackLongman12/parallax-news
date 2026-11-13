"""Edit list for the 1-minute cut.

The short film keeps only the bars of the full film where something happens.
Video and music are cut at exactly the same film times (snapped to the 60 fps
frame grid), so the picture stays locked to the song.

  python edl.py            -> prints the --edl string, length and splice points
  python edl.py audio OUT  -> writes the cut, faded music to OUT
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).parent
FPS = 60
b = json.loads((ROOT / "beats.json").read_text())
BAR0, BAR = b["bars"][0], b["beat"] * 4

# [from bar, to bar) of the full film, in order
KEEP = [
    (0, 1),      # logo pops
    (7, 10),     # crash zoom into the drop, one story / three sides, the three headlines
    (11, 12),    # headlines collapse into the lean bar
    (13, 15),    # feed with its callouts
    (19, 23),    # story page callouts, sources phone with ratings
    (24, 25),    # Blindspots title
    (26, 28),    # Blindspots phone and tiles
    (33, 36),    # from the world to your street, gates, Hackney
    (37, 39),    # local outlets
    (40, 42),    # no account / ads / tracking / paywall
    (43, 48),    # open source, finale
]


def snap(bar):
    return round((BAR0 + bar * BAR) * FPS) / FPS


SEGS = [(snap(a), snap(c)) for a, c in KEEP]
FRAMES = sum(round(c * FPS) - round(a * FPS) for a, c in SEGS)
LENGTH = FRAMES / FPS


def edl_arg():
    return ",".join(f"{a:.6f}:{c:.6f}" for a, c in SEGS)


def audio(out):
    song = ROOT.parent / "music" / "song.wav"
    parts, labels = [], []
    for i, (a, c) in enumerate(SEGS):
        d = c - a
        # 6 ms fades at every splice so the cuts don't click; total length unchanged
        parts.append(f"[0:a]atrim={a:.6f}:{c:.6f},asetpts=PTS-STARTPTS,"
                     f"afade=t=in:d=0.006,afade=t=out:st={d - 0.006:.6f}:d=0.006[s{i}]")
        labels.append(f"[s{i}]")
    fade = 4.0
    graph = ";".join(parts) + ";" + "".join(labels) + f"concat=n={len(SEGS)}:v=0:a=1,afade=t=out:st={LENGTH - fade:.3f}:d={fade}[out]"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(song), "-filter_complex", graph, "-map", "[out]",
                    "-c:a", "pcm_s16le", str(out)], check=True)


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "audio":
        audio(sys.argv[2])
    else:
        print("edl", edl_arg())
        print("length", f"{LENGTH:.3f}", "frames", FRAMES, "bars", sum(c - a for a, c in KEEP))
        t = 0.0
        for a, c in SEGS[:-1]:
            t += round(c * FPS) / FPS - round(a * FPS) / FPS
            print("splice at", f"{t:.3f}")
