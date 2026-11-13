"""BPM / beat / energy analysis of song.wav -> beats.json (for the video)."""
import json
import pathlib

import librosa
import numpy as np

HERE = pathlib.Path(__file__).parent
y, sr = librosa.load(HERE / "song.wav", sr=22050, mono=True, duration=150)
hop = 512

onset = librosa.onset.onset_strength(y=y, sr=sr, hop_length=hop)
tempo, beats = librosa.beat.beat_track(onset_envelope=onset, sr=sr, hop_length=hop, units="frames")
tempo = float(np.atleast_1d(tempo)[0])
beat_t = librosa.frames_to_time(beats, sr=sr, hop_length=hop)

# Regularise: fit a straight beat grid to the tracked beats (least squares),
# so scene cuts land exactly on the pulse even where tracking wobbles.
idx = np.arange(len(beat_t))
period, offset = np.polyfit(idx, beat_t, 1)
grid = offset + period * np.arange(-2, int(150 / period) + 4)
grid = grid[grid >= 0]

# Downbeat phase: which of the 4 beat positions has the most low-end punch.
S = np.abs(librosa.stft(y, hop_length=hop))
freqs = librosa.fft_frequencies(sr=sr)
low = S[freqs < 150].sum(axis=0)
low_t = librosa.frames_to_time(np.arange(len(low)), sr=sr, hop_length=hop)
def at(t):
    return low[min(np.searchsorted(low_t, t), len(low) - 1)]
phase = max(range(4), key=lambda p: sum(at(t) for t in grid[p::4]))
bars = grid[phase::4]

# Energy per frame (for EQ bars / pulses), 30 fps, plus 8 band levels.
fps = 30
rms = librosa.feature.rms(y=y, hop_length=hop)[0]
rms_t = librosa.frames_to_time(np.arange(len(rms)), sr=sr, hop_length=hop)
frames_t = np.arange(0, 150, 1 / fps)
energy = np.interp(frames_t, rms_t, rms)
energy = (energy / np.percentile(energy, 98)).clip(0, 1)
mel = librosa.feature.melspectrogram(S=S**2, sr=sr, n_mels=8)
mel = librosa.power_to_db(mel, ref=np.max)
mel = ((mel + 60) / 60).clip(0, 1)
bands = [np.interp(frames_t, rms_t[: mel.shape[1]], mel[b]).round(3).tolist() for b in range(8)]

# Section energy per 8 bars, to find the build / drop.
sections = []
for i in range(0, len(bars) - 1, 8):
    a, b = bars[i], bars[min(i + 8, len(bars) - 1)]
    m = (frames_t >= a) & (frames_t < b)
    sections.append({"bar": i, "t": round(float(a), 3), "energy": round(float(energy[m].mean()), 3)})

out = {
    "tempo_librosa": round(tempo, 2),
    "bpm": round(60 / period, 2),
    "beat": round(float(period), 5),
    "first_beat": round(float(grid[0]), 4),
    "downbeat_phase": phase,
    "bars": [round(float(t), 4) for t in bars],
    "fps": fps,
    "energy": energy.round(3).tolist(),
    "bands": bands,
    "sections": sections,
}
(HERE / "beats.json").write_text(json.dumps(out))
print("librosa tempo", round(tempo, 2), "| grid bpm", out["bpm"], "| beat", out["beat"], "s | first bar at", out["bars"][0])
for s in sections:
    print(f"bar {s['bar']:3d}  {s['t']:7.2f}s  energy {s['energy']:.2f}  " + "#" * int(s["energy"] * 40))
