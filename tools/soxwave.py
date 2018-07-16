#!/usr/bin/env python3

def _open(filename, mode='r'):
    return (Wave_write(filename)
            if mode.startswith('w')
            else Wave_read(filename))

class SoxError(IOError):
    pass

def sox_spawn(argv, data=None, **popenkwargs):
    import subprocess
    
    stdin_file = subprocess.PIPE if data else None
    
    child = subprocess.Popen(argv,
                             stdin=stdin_file,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             **popenkwargs)
    (out, err) = child.communicate(data if data else None)
    return (out, err, child.returncode)

def soxi_measure(filename):
    """Measure a wave and return a tuple (channels, rate, samples)."""
    soxiout = []
    for measure in ['-c', '-r', '-s']:
        argv = ['sox', '--info', measure, filename]
        (stdout, stderr, result) = sox_spawn(argv)
        if result != 0:
            raise SoxError(stderr.strip())
        soxiout.append(int(stdout))
    return soxiout

class Wave_read(object):

    def __init__(self, filename):
        self.crs = soxi_measure(filename)
        argv = ['sox', filename,
                '-t', 's16', '-L', '-']

        (stdout, stderr, result) = sox_spawn(argv, '')
        stderr = stderr.strip()
        if result > 0:
            raise SoxError(stderr)
        if stderr:
            print(stderr, file=sys.stderr)
        self.data = stdout
        self.pos = 0

    def close(self):
        "Dispose of the stream and make it unusable."
        self.crs = None
        self.data = None
        self.pos = None

    def getnchannels(self):
        "Return the number of channels in the wave."
        return self.crs[0]

    def getsampwidth(self):
        "Return sample width in bytes. This is always 2 due to SoX conversion."
        return 2

    def getframerate(self):
        "Return the number of frames in each second."
        return self.crs[1]

    def getnframes(self):
        "Return the number of frames in each file."
        return self.crs[2]

    __len__ = getnframes

    def getcomptype(self):
        "Return a code for the compression type."
        return 'NONE'

    def getcompname(self):
        "Return a localized name for the compression type."
        return 'not compressed'

    def getparams(self):
        "Return a tuple (nchannels, sampwidth, framerate, nframes, comptype, compname)."
        return (self.getnchannels(), self.getsampwidth(), self.framerate(),
                self.getnframes(), self.getcomptype(), self.getcompname())

    def readframes(self, n=None):
        "Read a string of bytes making up to n frames in little-endian format."
        n = (n * self.crs[0] * 2 if n is not None else None)
        pos = self.pos
        remain = len(self.data) - pos
        if n is None or n > remain:
            n = remain
        self.pos += n
        return self.data[pos:pos + n]

    def rewind(self):
        "Seek to the start of the wave."
        self.pos = 0

    def tell(self):
        "Save a read position in an implementation-defined format."
        return self.pos

    def setpos(self, pos):
        "Seek to a read position returned by tell()."
        self.pos = pos

    def getmarkers(self):
        "Return None, for compatibility with import aifc."
        return None

    def getmark(self, index):
        "Raise an error, for compatibility with import aifc."
        raise NotImplementedError

def open(filename, mode=None):
    """If mode is 'r', open an audio file for reading.

filename -- a file path, not a file-like object

Return a class instance with methods similar to those of the instance
returned by wave.open().
"""
    if not isinstance(mode, str):
        raise TypeError("mode must be a string")
    if not mode.startswith('r'):
        raise ValueError("unsupported mode %s (try 'r')" % repr(mode))
    return Wave_read(filename)

def get_sox_path():
    """Search folders on the PATH for the "sox" program.

Return the path to "sox" (or "sox.exe" on Windows) or None if not found.

Per https://stackoverflow.com/a/377028/2738262
"""
    import sys
    import os
    program = "sox.exe" if sys.platform == "win32" else "sox"
    
    for path in os.environ["PATH"].split(os.pathsep):
        exe_file = os.path.join(path, program)
        if os.path.isfile(exe_file) and os.access(fpath, os.X_OK):
            return exe_file

def _main():
    from binascii import b2a_hex
    w = _open('fine punch.wav', 'r')
    rate = w.getframerate()
    print(len(w), 'samples or', 1000*len(w)//rate, 'ms')
    r = w.readframes(1000)
    print(len(r), 'bytes read')
    for i in xrange(0, len(r), 32):
        print(b2a_hex(r[i:i + 32]))
    
if __name__=='__main__':
    _main()
else:
    open = _open
