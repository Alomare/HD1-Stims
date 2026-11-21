"""Writes src/sounds.lua: the stim sound's variants as Lua strings, so the mod carries them without sound
files beside the scripts. One variant plays at random with each stim.

Usage: python tools/build_sound.py <wav> [<wav> ...]

With no files, the WAVs in internal/sound (the last ones used) are read again. Each source goes through
ffmpeg: stereo, 16-bit, 48 kHz (the recording as it is), no tags, raised to a peak of -1 dB, then written as the plain 44-byte
WAV that src/sound.lua reads (RIFF, fmt and data and nothing else).
"""
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEEP = ROOT / "internal" / "sound"
OUT = ROOT / "src" / "sounds.lua"
RATE = 48000
CHANNELS = 2


def ffmpeg(*args):
    return subprocess.run(["ffmpeg", "-hide_banner", "-y", *args], check=True, capture_output=True, text=True)


def plain(source, tmp):
    raw = tmp / "raw.wav"
    ffmpeg("-i", str(source), "-ac", str(CHANNELS), "-ar", str(RATE), "-c:a", "pcm_s16le", "-map_metadata", "-1",
           "-fflags", "+bitexact", "-flags:a", "+bitexact", str(raw))
    probe = subprocess.run(["ffmpeg", "-hide_banner", "-i", str(raw), "-af", "volumedetect", "-f", "null", "-"],
                           capture_output=True, text=True).stderr
    peak = float(probe.split("max_volume:")[1].split("dB")[0])
    done = tmp / "done.wav"
    ffmpeg("-i", str(raw), "-af", f"volume={-1 - peak}dB", "-c:a", "pcm_s16le", "-map_metadata", "-1",
           "-fflags", "+bitexact", "-flags:a", "+bitexact", str(done))
    data = done.read_bytes()
    assert data[:4] == b"RIFF" and data[8:16] == b"WAVEfmt " and data[36:40] == b"data", "a plain 44-byte WAV"
    return data


def lua_string(data):
    lines = []
    for i in range(0, len(data), 64):
        lines.append('"' + "".join(f"\\{b}" for b in data[i:i + 64]) + '"')
    return "table.concat({\n\t\t" + ",\n\t\t".join(lines) + ",\n\t})"


def main():
    sources = [Path(a) for a in sys.argv[1:]]
    if sources:
        shutil.rmtree(KEEP, ignore_errors=True)
        KEEP.mkdir(parents=True)
        for i, s in enumerate(sources, 1):
            shutil.copy(s, KEEP / f"{i}_{s.name}")
    sources = sorted(KEEP.glob("*.wav"))
    assert sources, "no sound sources"
    tmp = ROOT / "internal" / "sound_tmp"
    tmp.mkdir(parents=True, exist_ok=True)
    variants = [plain(s, tmp) for s in sources]
    shutil.rmtree(tmp)
    body = ",\n\t".join(lua_string(v) for v in variants)
    OUT.write_text(
        "-- The stim sound variants: stereo 16-bit 48 kHz WAVs, written by tools/build_sound.py. Do not edit.\n"
        "return {\n\t" + body + ",\n}\n", encoding="utf-8", newline="\n")
    print(OUT, len(variants), "variants", sum(len(v) for v in variants), "bytes")


if __name__ == "__main__":
    main()
