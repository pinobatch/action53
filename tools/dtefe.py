#!/usr/bin/env python3
"""
Python frontend for JRoatch's C language DTE compressor
license: zlib
"""
import sys, os, subprocess

def dte_compress(lines, compctrl=False, mincodeunit=128):
    dte_path = os.path.join(os.path.dirname(__file__), "dte")
    delimiter = b'\0'
    if len(lines) > 1:
        unusedvalues = set(range(1 if compctrl else 32))
        for line in lines:
            unusedvalues.difference_update(line)
        delimiter = min(unusedvalues)
        delimiter = bytes([delimiter])
    excluderange = "0x00-0x00" if compctrl else "0x00-0x1F"
    digramrange = "0x%02x-0xFF" % mincodeunit
    compress_cmd_line = [
        dte_path, "-c", "-e", excluderange, "-r", digramrange
    ]
    inputdata = delimiter.join(lines)
    spresult = subprocess.run(
        compress_cmd_line, check=True,
        input=inputdata, stdout=subprocess.PIPE
    )
    table_len = (256 - mincodeunit) * 2
    repls = [spresult.stdout[i:i + 2] for i in range(0, table_len, 2)]
    clines = spresult.stdout[table_len:].split(delimiter)
    return clines, repls, None

def dte_uncompress(line, replacements, mincodeunit=128):
    outbuf = bytearray()
    s = []
    maxstack = 0
    for c in line:
        s.append(c)
        while s:
            maxstack = max(len(s), maxstack)
            c = s.pop()
            if 0 <= c - mincodeunit < len(replacements):
                repl = replacements[c - mincodeunit]
                s.extend(reversed(repl))
##                print("%02x: %s" % (c, repr(repl)), file=sys.stderr)
##                print(repr(s), file=sys.stderr)
            else:
                outbuf.append(c)
    return bytes(outbuf), maxstack

# Compress for for robotfindskitten
def nki_main(argv=None):
    import heapq
    from vwfbuild import ca65_bytearray

    # Load input files
    argv = argv or sys.argv
    lines = []
    for filename in argv[1:]:
        with open(filename, 'rU') as infp:
            lines.extend(row.strip() for row in infp)

    # Remove blank lines and comments
    lines = [row.encode('ascii')
             for row in lines
             if row and not row.startswith('#')]

    # Diagnostic for line length.  RFK RFC forbids lines longer than
    # 72 characters, and longer lines may wrap to more than 3 lines.
    lgst = heapq.nlargest(10, lines, len)
    if len(lgst[0]) > 72:
        print("Some NKIs are too long (more than 72 characters):", file=sys.stderr)
        print("\n".join(line for line in lgst if len(line) > 72), file=sys.stderr)
    else:
        print("Longest NKI is OK at %d characters. Don't let it get any longer."
              % len(lgst[0]), file=sys.stderr)
        print(lgst[0], file=sys.stderr)

    oldinputlen = sum(len(line) + 1 for line in lines)

    lines, replacements, _ = dte_compress(lines)

    finallen = len(replacements) * 2 + sum(len(line) + 1 for line in lines)
    stkd = max(dte_uncompress(line, replacements)[1] for line in lines)
    print("from %d to %d bytes with peak stack depth: %d"
          % (oldinputlen, finallen, stkd), file=sys.stderr)

    replacements = b''.join(replacements)
    num_nkis = len(lines)
    lines = b''.join(line + b'\x00' for line in lines)
    outfp = sys.stdout
    outfp.write("""; Generated with dte.py; do not edit
.export NUM_NKIS, nki_descriptions, nki_replacements
NUM_NKIS = %d
.segment "NKIDATA"
nki_descriptions:
%s
nki_replacements:
%s
""" % (num_nkis, ca65_bytearray(lines), ca65_bytearray(replacements)))

def main(argv=None):
    argv = argv or sys.argv
    with open(argv[1], "rb") as infp:
        lines = [x.rstrip(b"\r\n") for x in infp]
    clines, repls = dte_compress(lines)[:2]
    print(clines)
    print(repls)

if __name__=='__main__':
    if 'idlelib' in sys.modules:
        nki_main([sys.argv[0], "../../rfk/src/fixed.nki", "../../rfk/src/default.nki"])
    else:
        nki_main()
