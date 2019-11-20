#!/usr/bin/env python3
from contextlib import closing
import sys
import array
import argparse

# Use SoX
import wave as wavewriter
try:
    import soxwave
except ImportError:
    sox_path = None
else:
    sox_path = soxwave.get_sox_path()
if sox_path:
    wave = soxwave
else:
    soxwave = None
    import wave

framelen = (256 - 1) * 4
little = array.array("i",[1]).tobytes()[0]
assert isinstance(little, int)

def load_file(filename):
    with closing(wave.open(filename, "r")) as inwv:
        c = inwv.getnchannels()
        if c != 1:
            raise ValueError("only mono is supported, not %d channels" % c)
        c = inwv.getsampwidth()
        if c != 2:
            raise ValueError("only 16 bit is supported, not %d bit" % (8 * c))
        nframes = inwv.getnframes()
        data = array.array('h', inwv.readframes(nframes))
    if not little:
        data.byteswap()
    return data

def play_data(data, rate):
    if not little:
        data = data[:]
        data.byteswap()
    args = ['play', '-t', 's16', '-r', str(rate), '-c', '1', '-L', '-']
    wave.sox_spawn(args, data.tostring())

def save_wave_as_mono16(filename, freq, data):
    data = array.array('h', (min(max(s, -32767), 32767) for s in data))
    if not little:
        data.byteswap()
    with closing(wavewriter.open(filename, "wb")) as outfp:
        outfp.setnchannels(1)
        outfp.setsampwidth(2)
        outfp.setframerate(freq)
        outfp.writeframes(data.tobytes())

deltas = [0, 1, 4, 9, 16, 25, 36, 49,
          64, -49, -36, -25, -16, -9, -4, -1]
def quadpcm_enc(data, startval=64):
    """Encode one packet"""
    out = bytearray()
    scmin = 64
    scmax = 64
    byt = None
    for s in data:
        scaled = min((s + 32768 + 64) // 512, 127)
        cands = [(abs(((startval + d) & 0x7F) - scaled), i)
                  for (i, d) in enumerate(deltas)]
        enc = min(cands)[1]
        if byt is None:
            byt = enc
        else:
            out.append(byt | (enc << 4))
            byt = None
        startval = (startval + deltas[enc]) & 0x7F
    return (bytes(out), startval)

def quadpcm_dec(data, startval=64):
    """Decode one packet"""
    out = array.array('h')
    for c in data:
        for enc in (c & 0x0F, c >> 4):
            startval = (startval + deltas[enc]) & 0x7F
            out.append((startval - 64) * 512)
    return (out, startval)

def halve_rate(iterable):
    """Convolve with [-1 0 9 16 9 0 -1]/32 and decimate by 2"""
    flp = array.array('h', [0] * 3)
    flp.extend(iterable)
    flp.extend([0]*3)
    fil = (int(round((16 * flp[i + 3]
                      - (flp[i] + flp[i + 6])
                      + 9 * (flp[i + 2] + flp[i + 4]))
                     / 32))
           for i in range(0, len(flp) - 6, 2))
    return array.array('h', fil)

def lerp_double_rate(iterable):
    """Double rate with linear interpolation"""
    fil = array.array('h', iterable)
    fil.append(0)
    lerp1 = ((a, (a + b) // 2)
             for (a, b) in zip(fil[:-1], fil[1:]))
    return array.array('h', (s for r in lerp1 for s in r))

def quads_enc(data):
    data_frames = [data[i:i + framelen]
                   for i in range(0, len(data), framelen)]
    del data

    # For each frame, I choose only low frequencies (0-4000 Hz)
    # or high frequencies (4000-8000 Hz), not both.
    # Use autocorrelation at lag 1 to see which to use.
    correls = [(sum(a * b for (a, b) in zip(f[1:], f[:-1]))
                / sum(a * a for a in f))
               for f in data_frames]
    # flip_frames: these frames shall be decoded with the
    # interpolated samples flipped
    flip_frames = [r < 0 for r in correls]
    flp1 = (-s if (flip and (i & 1)) else s
            for (f, flip) in zip(data_frames, flip_frames)
            for (i, s) in enumerate(f))
    fil = halve_rate(flp1)
    correls = flp1 = None

    fil_frames = [fil[i:i + framelen // 2]
                  for i in range(0, len(fil), framelen // 2)]

    # At this point, the signal is (fil, flip_frames)
    # Encode bitstream
    bitstream = array.array('B')
    last = 64
    for i in range(len(flip_frames)):
        base = framelen // 2 * i
        f = fil[base:base + framelen // 2]
        flipval = 0x7F if flip_frames[i] else 0
##        print("frame %d flip %02x" % (i, flipval))
        bitstream.append(flipval)
        (enc, last) = quadpcm_enc(f, last)
        bitstream.fromstring(enc)
    return bitstream

def quads_dec(bitstream):

    # Validation to see if we can decode this bitstream.
    enc_frames = [bitstream[i:i + framelen // 4 + 1]
                  for i in range(0, len(bitstream), framelen // 4 + 1)]
    del bitstream
    flip_frames = [f[0] for f in enc_frames]
    fil = array.array('h')
    last = 64
    for f in enc_frames:
        (dec, last) = quadpcm_dec(f[1:], last)
        fil.extend(dec)

    # Reconstruct at full rate
    lerp = lerp_double_rate(fil)
    lerp_frames = [lerp[i:i + framelen]
                   for i in range(0, len(lerp), framelen)]
    unflp = (min(32767, -s if (flip and (i & 1)) else s)
             for (f, flip) in zip(lerp_frames, flip_frames)
             for (i, s) in enumerate(f))
    return array.array('h', unflp)

def parse_argv(argv):
    a = argparse.ArgumentParser()
    a.add_argument("infile")
    a.add_argument("outfile")
    a.add_argument("-d", "--decode", action="store_true",
                   help="convert qdp to wav (default: wav to qdp)")
    return a.parse_args(argv[1:])

def main(argv=None):
    args = parse_argv(argv or sys.argv)
    infilename = args.infile
    outfilename = args.outfile
    if args.decode:
        with open(infilename, "rb") as infp:
            bitstream = infp.read()
        wavedata = quads_dec(bitstream)
        save_wave_as_mono16(outfilename, 16000, wavedata)
    else:
        wavedata = load_file(infilename)
        bitstream = quads_enc(wavedata)
        if len(bitstream) % 256 > 0:
            bitstream.extend([0] * (256 - (len(bitstream) % 256)))
        with open(outfilename, "wb") as outfp:
            outfp.write(bitstream.tostring())

if __name__=='__main__':
    main()
