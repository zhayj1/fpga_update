"""Extract exact pre-gain left-channel PCM windows for the RTL FFT probe."""

import struct
import wave
from pathlib import Path


TIMES = tuple(range(45))
ROOT = Path(__file__).resolve().parents[1]

with wave.open(str(ROOT / "card/S01.WAV"), "rb") as source:
    assert source.getframerate() == 48000
    assert source.getnchannels() == 2 and source.getsampwidth() == 2
    lines = ["000"] * 1024
    for second in TIMES:
        source.setpos(second * 48000)
        raw = source.readframes(1024)
        pcm = struct.unpack("<2048h", raw)
        lines.extend("{:03x}".format((pcm[i] >> 4) & 0xFFF) for i in range(0, 2048, 2))

(ROOT / "sim/color_wav_probe.mem").write_text("\n".join(lines) + "\n", encoding="ascii")
print("Generated {} FFT windows: silence, {}".format(len(TIMES) + 1, TIMES))
