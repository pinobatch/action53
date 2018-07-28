#!/usr/bin/env python3
# "Donut", NES CHR codec,
# Copyright (C) 2018  Johnathan Roatch
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import os
import sys
import itertools
import functools

@functools.lru_cache(maxsize=None, typed=False)
def pb8_pack_plane(plane, top_value=0x00):
    """pack a 8 byte plane into a pb8 packet.

    The pb8 packet has a 1 byte header.
    for each bit in header:
        0: Duplicate the previous byte. The first previous byte is 0x00
        1: Take a new byte from the data stream.

    This variant encodes the tile upside down
    """
    cplane = bytearray(1)
    flags = 0
    prev_byte = top_value
    for byte in plane[7::-1]:
        flags = flags << 1
        if byte != prev_byte:
            flags = flags | 1
            cplane.append(byte)
        prev_byte = byte
    cplane[0] = flags
    return bytes(cplane)

@functools.lru_cache(maxsize=None, typed=False)
def flip_plane_bits_45(plane):
    return bytes(sum(((plane[x] >> (7-y))&0b1) << (7-x) for x in range(8)) for y in range(8))

@functools.lru_cache(maxsize=None, typed=False)
def flip_plane_bits_135(plane):
    return bytes(sum(((plane[x] >> y)&0b1) << x for x in range(8)) for y in range(8))

def pb8_unpack_plane(cplane, top_value=0x00):
    cplane_iter = iter(cplane)
    plane = bytearray(8)
    flags = next(cplane_iter)
    cur_byte = top_value
    for i in range(7,-1,-1):
        flags = flags << 1
        if flags & 0x0100:
            cur_byte = next(cplane_iter)
        plane[i] = cur_byte
    return bytes(plane)

def cblock_cost(cblock):
    block_header = cblock[0]
    cycle_data = [
        5353, 5755, 8753, 9159, 5449, 5851, 8757, 9163,
        5449, 5851, 8757, 9163, 5545, 5947, 8761, 9167,
        5773, 6175, 9229, 9635, 5869, 6271, 9233, 9639,
        5925, 6327, 9233, 9639, 6021, 6423, 9237, 9643,
        5753, 6155, 9209, 9615, 5905, 6307, 9213, 9619,
        5849, 6251, 9213, 9619, 6001, 6403, 9217, 9623,
    ]
    if block_header < 0xc0:
        return len(cblock)*10000 + cycle_data[block_header >> 2]
    else:
        if block_header & 1:
            return len(cblock)*10000 + 70
        else:
            return len(cblock)*10000 + 2118

def compress_block(input_block, prev_block=None, use_bit_flip=True):
    """Compresses a 64 byte block into a variable length coded block.

    The coded block starts with a 1 or 2 byte header,
    followed by at most 8 pb8 packets.

    Block header:
    MLIiRCpp
    ||||||00-- Another header byte. For each bit starting from MSB
    ||||||       0: 0x00 plane
    ||||||       1: pb8 plane
    ||||||01-- L planes: 0x00, M planes:  pb8
    ||||||10-- L planes:  pb8, M planes: 0x00
    ||||||11-- All planes: pb8
    |||||+---- 1: Clear block buffer, 0: XOR with existing block
    ||||+----- Rotate plane bits (135° reflection)
    |||+------ L planes predict from 0xff
    ||+------- M planes predict from 0xff
    |+-------- L = M XOR L
    +--------- M = M XOR L
    11111110-- Uncompressed block of 64 bytes
    11111111-- Reuse previous block (skip block)

    0xc0 <= header < 0xfe are Reserved and can be consumed as a no-op.
    """
    if len(input_block) < 64:
        raise ValueError("input block is less then 64 bytes.")
    if input_block == prev_block:
        return b'\xff'
    if prev_block is not None:
        if len(prev_block) < 64:
            raise ValueError("input previous block is less then 64 bytes.")
        xor_block = bytes( input_block[i] ^ prev_block[i] for i in range(64) )
    cblock_choices = [b'\xfe' + input_block[::-1]]
    for attempt_type in range(0, 0xc0, 4):
        if not use_bit_flip and attempt_type & 0x08:
            continue
        if attempt_type & 0x04:
            block = input_block
        elif prev_block:
            block = xor_block
        else:
            continue
        cblock = [b'']
        plane_def = 0
        for plane_l, plane_m in ((block[i+0:i+8], block[i+8:i+16]) for i in range(0,64,16)):
            plane_def = plane_def << 2
            if attempt_type & 0xc0 != 0x00:
                plane_xor = bytes( plane_l[i] ^ plane_m[i] for i in range(8) )
                if attempt_type & 0x40:
                    plane_l = plane_xor
                if attempt_type & 0x80:
                    plane_m = plane_xor
            if attempt_type & 0x08:
                plane_l, plane_m = flip_plane_bits_135(plane_l), flip_plane_bits_135(plane_m)
            if attempt_type & 0x10:
                cplane_l = pb8_pack_plane(plane_l, 0xff)
            else:
                cplane_l = pb8_pack_plane(plane_l, 0x00)
            if cplane_l != b'\x00':
                cblock.append(cplane_l)
                plane_def = plane_def | 2
            if attempt_type & 0x20:
                cplane_m = pb8_pack_plane(plane_m, 0xff)
            else:
                cplane_m = pb8_pack_plane(plane_m, 0x00)
            if cplane_m != b'\x00':
                cblock.append(cplane_m)
                plane_def = plane_def | 1
        short_planes_type = next((i for i, t in enumerate([0x00,0x55,0xaa,0xff]) if plane_def == t), 0)
        if short_planes_type == 0:
            cblock[0] = bytes([attempt_type, plane_def])
        else:
            cblock[0] = bytes([attempt_type + short_planes_type])
        cblock_choices.append(b''.join(cblock))
    return min(cblock_choices, key=cblock_cost)

def uncompress_block(cblock, prev_block=b'\x00'*64):
    cblock_iter = iter(cblock)
    if not prev_block:
        prev_block = b'\x00'*64
    block_header = next(cblock_iter)
    if 0xc0 <= block_header < 0xfe:
        raise ValueError("Unknown block type")
    block = bytearray(prev_block)
    if block_header >= 0xc0:
        if block_header & 0x01 == 0:
            for i in range(63,-1,-1):
                block[i] = next(cblock_iter)
    else:
        if block_header & 0x04:
            block = bytearray(64)
        plane_def = [0x00,0x55,0xaa,0xff][block_header & 0x03]
        if plane_def == 0x00:
            plane_def = next(cblock_iter)
        is_M_plane = False
        for block_offset in range(0,64,8):
            pb8_top_value = 0x00
            if block_header & 0x20 and is_M_plane:
                pb8_top_value = 0xff
            if block_header & 0x10 and not is_M_plane:
                pb8_top_value = 0xff
            if plane_def & 0x80:
                plane = pb8_unpack_plane(cblock_iter, pb8_top_value)
                if block_header & 0x08:
                    plane = flip_plane_bits_135(plane)
            else:
                plane = bytes([pb8_top_value]*8)
            is_M_plane = not is_M_plane
            for i, c in enumerate(plane):
                block[block_offset + i] ^= c
                if block_header & 0x80 and is_M_plane:
                    block[block_offset + i + 8] ^= c
                if block_header & 0x40 and not is_M_plane:
                    block[block_offset + i - 8] ^= c
            plane_def = (plane_def << 1) & 0xff
    return bytes(block)

class FileIterContextHack():
    def __init__(self, fn, mode, ask_file_overwrite=True):
        if fn == '-':
            if mode == 'rb':
                self.fd = sys.stdin.buffer
                self.file_name = "<stdin>"
            elif mode == 'wb' or mode == 'xb':
                self.fd = sys.stdout.buffer
                self.file_name = "<stdout>"
            self.file_size = 0
            self.exit_needs_closed = False
        else:
            self.file_name = fn
            if mode not in {'rb', 'wb', 'xb'}:
                raise ValueError("File mode must be binary.")
            try:
                self.fd = open(self.file_name, mode)
            except FileExistsError as error:
                if ask_file_overwrite:
                    print("{0} already exists; do you wish to overwrite (y/N) ? ".format(self.file_name), end='', file=sys.stderr)
                    overwrite_answer = input()
                else:
                    raise error
                if overwrite_answer[0:1].lower() == 'y':
                    self.fd = open(self.file_name, 'wb')
                else:
                    print("    not overwritten", file=sys.stderr)
                    sys.exit()
            self.file_size = os.stat(self.fd.fileno()).st_size
            self.exit_needs_closed = True
        self.read_iter = itertools.chain.from_iterable(
            iter(lambda: self.fd.read1(8192), b'')
        ) if mode == "rb" else None
        self.bytes_transfered = 0
    def __enter__(self):
        return self
    def __exit__(self, *args):
        if self.exit_needs_closed:
            self.fd.close()
    def __iter__(self):
        return self
    def __next__(self):
        byte = next(self.read_iter)
        self.bytes_transfered += 1
        return byte
    def __len__(self):
        return self.file_size
    def read(self, size=-1):
        bytes = self.fd.read(size)
        self.bytes_transfered += len(bytes)
        return bytes
    def write(self, b):
        number_written = self.fd.write(b)
        self.bytes_transfered += number_written
        return number_written

class ProgressBar():
    def __init__(self, file_name='', goal_val=0, begin_time=None, line_width=80):
        self.file_name = file_name
        self.current_val = 0
        self.goal_val = goal_val
        self.indeterminate = (goal_val <= 0)
        self.begin_time = begin_time
        self.w = line_width
        self.show_bar = False
        self.t = 0
        self.p = 0
        self.show_progress_bar = False
        self.print_ready = False
        self.last_print_time = 0

    def update(self, time, val):
        self.current_val = val
        self.t = time - self.begin_time
        if not self.indeterminate:
            self.p = val / self.goal_val
            # if progress is less then 33% per second or 100% in 3 seconds.
            if self.p / self.t <= 1/3 and self.t >= 1/4:
                self.show_progress_bar = True
        else:
            if self.t >= 2:
                self.show_progress_bar = True
        if self.show_progress_bar and round(self.t * 4) > self.last_print_time:
            self.print_ready = True
            self.last_print_time = round(self.t * 4)
        return self.print_ready

    def __bool__(self):
        return self.show_progress_bar

    def __str__(self):
        anim = [14, 17, 18, 17, 14, 9, 4, 1, 0, 1, 4, 9]
        self.print_ready = False
        if self.indeterminate:
            lpt = self.last_print_time % len(anim)
            bar_string = " {} [{}<==>{}] --:--".format(self.current_val, ' ' * anim[lpt], ' ' * (18-anim[lpt]))
        else:
            s = int(self.t * (1 - self.p) / self.p + 1)
            bar_string = " {}/{} [{:-<22}] {:0>2}:{:0>2}".format(self.current_val, self.goal_val, "#" * int(self.p*22), s//60, s%60)
        space_left = self.w - len(bar_string)
        if len(self.file_name) <= space_left:
            inner_margin = ' ' * (space_left - len(self.file_name))
            return "".join([self.file_name, inner_margin, bar_string])
        else:
            return "".join([self.file_name[:(space_left-3)], "..." , bar_string])

    def clear_spaces(self):
        return ' ' * self.w

def main(argv=None):
    import argparse
    import time

    parser = argparse.ArgumentParser(description='Donut NES Codec', usage='%(prog)s [options] [-d] input [-o] output')
    parser.add_argument('--version', action='version', version='%(prog)s 1.0')
    parser.add_argument('input', metavar='files', help='Input files', nargs='*')
    parser.add_argument('-d', '--decompress', help='decompress the input files', action='store_true')
    parser.add_argument('-o', '--output', metavar='FILE', help='output to FILE instead of last positional argument')
    parser.add_argument('-f', '--force',  help='overwrite output without prompting', action='store_true')
    #parser.add_argument('-v', '--verbose', action='count', default=1, help='Display progress bar, (repeat for extra verbosity)')
    parser.add_argument('-q', '--quiet', help='suppress progress bar and completion message', action="store_true")
    parser.add_argument('--no-prev', help="don't encode references to previous block", action="store_true")
    parser.add_argument('--no-bit-flip', help="don't encode plane flipping", action="store_true")
    #parser.add_argument('--no-page-interleave', help="don't interleave pages when [de]compressing", action="store_true")
    #parser.add_argument('--add-seek-points', metavar='BLOCKS_PER_PAGE', help='disable interleaving and begin with a list of byte offsets to pages')
    options = parser.parse_args(argv)

    if not options.output and len(options.input) > 1:
        options.output = options.input.pop()
    if '-' not in options.input and not sys.stdin.isatty():
        options.input.append('-')
    if options.output is None and not sys.stdout.isatty():
        options.output = '-'
    if not options.input or not options.output:
        if not options.quiet:
            parser.print_usage(file=sys.stderr)
        sys.exit(1)

    screen_width = os.get_terminal_size(sys.stderr.fileno()).columns

    output_file_mode = 'wb' if options.force else 'xb'
    ask_for_overwrite = not options.quiet and sys.stdin.isatty()
    with FileIterContextHack(options.output, output_file_mode, ask_for_overwrite) as output_file:
        total_input_bytes = 0
        total_output_bytes = 0
        for fn in options.input:
            with FileIterContextHack(fn, 'rb') as input_file:
                progress = ProgressBar(input_file.file_name, len(input_file), time.time(), screen_width)
                if options.decompress:
                    page = []
                    prev_block = None
                    for block in (uncompress_block(input_file, prev_block) for _ in iter(int, 1)):
                        page.append(block)
                        if not options.quiet:
                            if progress.update(time.time(), input_file.bytes_transfered):
                                print(progress, end='\r', file=sys.stderr)
                        prev_block = block
                        if len(page) >= 256:
                            output_file.write(b''.join(page))
                            page.clear()
                    if len(page) > 0:
                        output_file.write(b''.join(page))
                else:
                    for page in iter(lambda: input_file.read(256*64), b''):
                        cpage = []
                        prev_block = None
                        page_padding = 0
                        for block in (page[i:i+64] for i in range(0, len(page), 64)):
                            if len(block) < 64:
                                if not options.quiet:
                                    print("Warning: The last block of a page was less then 64 bytes. Filling with zeros.", file=sys.stderr)
                                page_padding = 64-len(block)
                                block = block + bytes(page_padding)
                            cblock = compress_block(block, prev_block, not options.no_bit_flip)
                            #block_check = uncompress_block(cblock, prev_block)
                            #assert block == block_check, ["mismatch between compress_block and uncompress_block", block, block_check, cblock]
                            cpage.append(cblock)
                            if not options.quiet:
                                if progress.update(time.time(), input_file.bytes_transfered):
                                    print(progress, end='\r', file=sys.stderr)
                            if not options.no_prev:
                                prev_block = block
                        output_file.write(b''.join(cpage))

                if not options.quiet:
                    r = input_file.bytes_transfered
                    w = output_file.bytes_transfered - total_output_bytes
                    if progress:
                        print(progress.clear_spaces(), end='\r', file=sys.stderr)
                    try:
                        ratio = 1 - (r / w) if options.decompress else 1 - (w / r)
                    except ZeroDivisionError:
                        if r == w:
                            ratio = 0
                        else:
                            ratio = float('NaN')
                    print("{} :{:>6.1%} ({} => {} bytes, {})".format(input_file.file_name, ratio, r, w, output_file.file_name), file=sys.stderr)
                    total_input_bytes += r
                    total_output_bytes += w
        if not options.quiet and len(options.input) > 1:
            r = total_input_bytes
            w = total_output_bytes
            ratio = 1-(r / w) if options.decompress else 1-(w / r)
            print("<total> :{:>6.1%} ({} => {} bytes, {})".format(ratio, r, w, output_file.file_name), file=sys.stderr)

def debug_generate_cpu_test(output_filename):
    test_tile = b'~HET$EH\x00>~HET~$\x00'
    with open(output_filename, 'wb') as output_donut:
        const_data = (pb8_pack_plane(test_tile[0:8]) + pb8_pack_plane(test_tile[8:16]))*4
        for i in range(0, 0xc0, 4):
            output_donut.write(bytes([i+3]) + const_data)

def debug_cblock_diagnostics(cblock):
    output_line = []
    cblock_iter = iter(cblock)
    block_header = next(cblock_iter)
    if block_header < 0xc0:
        output_line.append(''.join("MLIiRCpp"[i] if (block_header<<i)&0x80 else '-' for i in range(8)))
        if block_header & 0x03 == 0x00:
            plane_def = next(cblock_iter)
            output_line.append(',{:02x}'.format(plane_def))
        else:
            plane_def = [0x00,0x55,0xaa,0xff][block_header & 0x03]
        output_line.append(':')
        for i in range(8):
            if (plane_def<<i)&0x80:
                pb8_head = next(cblock_iter)
                output_line.append(' <{:02x}|'.format(pb8_head))
                output_line.append(''.join("{:02x}".format(next(cblock_iter)) for _ in range(bin(pb8_head).count('1'))))
                output_line.append('>')
    elif 0xc0 <= block_header < 0xfe:
        output_line.append(''.join("########"[i] if (block_header<<i)&0x80 else '-' for i in range(8)))
        output_line.append(':')
    else:
        if block_header == 0xfe:
            output_line.append('##---raw: ')
            output_line.append(''.join("{:02x}".format(next(cblock_iter)) for _ in range(64)))
        else:
            output_line.append('##--skip:')
    #output_line.append('\n')
    return ''.join(output_line)

def debug_print_block(tile):
    print("\n".join("  ".join("".join("0123"[((tile[b*16+y+0]>>(7-x))&1 | ((tile[b*16+y+8]>>(7-x))&1)<<1)] for x in range(8)) for b in range(4)) for y in range(8)))

debug_test_block = b'\x00\x00\x00\x02\x07\x07\x03\x01\x0f\x1f?????\x17\x00\x00@\xe8\xf8\xf8\xf0\xe0\xf0\xf8\xfc\xfcXX\xf8\xfc\xff\xff\xef\x0f\x1f?\x1f\x0f\r\x0e\x0e\x00\x00\x04\x0e\x0f\xc0\xe0\xf0\xf0\xf8\xfc\xf8x\xc0\x00\x00\x00\x00 px'
debug_orientation_test_block = b'8@@HH@@@@@@@X@@@'*4

#spam = FileIterContextHack("result.donut", 'rb')
#print("\n".join(debug_cblock_diagnostics(spam) for _ in iter(int, 1)))

if __name__ == "__main__":
    main()
