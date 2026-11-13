#!/bin/bash
# Renders the film in 10 s chunks (fresh Edge each), skipping chunks already done.
#   ./render_all.sh                 -> part_000.mp4 ...
#   ./render_all.sh flat --flat 1   -> flat_000.mp4 ... (flat cut)
cd "$(dirname "$0")"
NAME=${1:-part}; shift
END=125.43
for s in $(seq 0 10 120); do
  e=$(python -c "print(min($s+10, $END))")
  out=$(printf "%s_%03d.mp4" "$NAME" $s)
  if [ -f "$out.ok" ]; then continue; fi
  for attempt in 1 2 3; do
    echo "chunk $s-$e attempt $attempt $(date +%T)"
    if node render.js --from $s --to $e --fps 60 --preset slow --crf 16 --out $out "$@" > "log_${NAME}_$s.txt" 2>&1 && ffprobe -v error "$out" >/dev/null 2>&1; then
      touch "$out.ok"; break
    fi
    tail -3 "log_${NAME}_$s.txt"
  done
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='msedge.exe'\" | Where-Object { \$_.CommandLine -like '*scratchpad*edgeprof-*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
done
ls ${NAME}_*.mp4.ok | wc -l
