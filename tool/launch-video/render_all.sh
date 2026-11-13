#!/bin/bash
# Renders the film in 10 s chunks (fresh Edge each), skipping chunks already done.
cd "$(dirname "$0")"
END=125.43
for s in $(seq 0 10 120); do
  e=$(python -c "print(min($s+10, $END))")
  out=$(printf "part_%03d.mp4" $s)
  if [ -f "$out.ok" ]; then continue; fi
  for attempt in 1 2 3; do
    echo "chunk $s-$e attempt $attempt $(date +%T)"
    if node render.js --from $s --to $e --fps 60 --preset slow --crf 16 --out $out > "log_$s.txt" 2>&1 && ffprobe -v error "$out" >/dev/null 2>&1; then
      touch "$out.ok"; break
    fi
    tail -3 "log_$s.txt"
  done
  powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='msedge.exe'\" | Where-Object { \$_.CommandLine -like '*scratchpad*edgeprof-*' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }" >/dev/null 2>&1
done
ls part_*.mp4.ok | wc -l
