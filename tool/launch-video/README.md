# Launch video

A 2-minute launch film rendered from HTML, synced to "So Good" by LEVEL NINE at 92.36 BPM.

- `analyze.py` measures BPM, beats, bars and per-frame energy from `song.wav` and writes `beats.json`.
- `index.html` and `app.js` hold the whole film. It is one 3D world the camera flies through, and every scene change lands on a bar. `frame(t)` draws the frame at time `t`, so rendering is fully deterministic.
- `render.js` drives headless Edge frame by frame and pipes the frames to ffmpeg. If a frame capture hangs, it kills Edge, relaunches it and captures that frame again. It also starts a fresh Edge every 5 seconds of footage.
- `index.html?flat` is the flat cut. It uses solid colour scenes with flat wipes, and has no glow, gloss, grain or stars. Its camera track is mostly locked-off shots with hard cuts on the beat, plus one distinct move per scene. Render it with `--flat 1` (for example `./render_all.sh flat --flat 1`).
- `index.html?short` is the 1-minute-10 cut. It has the flat look and one continuous camera flight, with no cuts.
  - `WARP` in `app.js` retimes the full film. It squeezes the holds and keeps the busy moments at full speed, so every big moment still lands on a beat.
  - The music is one unbroken stretch of the song starting at bar 4, so the drop lands on "One story".
  - To render it:

    ```
    END=70.866667 ./render_all.sh cont --short 1
    ffmpeg -ss 10.39392 -t 70.866667 -i song.wav -af "afade=t=out:st=66.4:d=4.4" song_cont.wav
    ```
- `render_all.sh` renders the film in 10-second chunks. It skips chunks that are already done, so you can re-run it after a failure.

## Rebuild

1. Copy the app screenshots into `img/` (CI's `screenshots` artifact) and the Inter fonts into `fonts/` (from `assets/fonts`).
2. Run `npm install` to get puppeteer-core.
3. Download the song as `song.wav`, then run `python analyze.py` (needs librosa).
4. Render the video and add the faded audio:

```
./render_all.sh
for f in part_*.mp4; do echo "file '$f'"; done > parts.txt
ffmpeg -f concat -safe 0 -i parts.txt -c copy video.mp4
ffmpeg -i video.mp4 -i song.wav -map 0:v -map 1:a -c:v copy -af "atrim=0:125.43,afade=t=out:st=118.5:d=6.6" -c:a aac -b:a 320k -shortest parallax-launch.mp4
```

To render single frames for checking: `node render.js --stills 10,25,60`. Add `--debug 1` to draw the camera values on each frame.

The song is not included in the repo (copyright).
