#!/usr/bin/env python3

def slices_union(seq):
    """Sort 2-tuples and combine them as if right-open intervals."""
    out = []
    for (start, end) in sorted(seq):
        if len(out) < 1 or out[-1][1] < start:
            out.append((start, end))
        else:
            out[-1] = (out[-1][0], end)
    return out

# slices_union([(5, 8), (12, 15), (3, 6), (10, 12)])
# should return (3, 8), (10, 15)

def slices_find(slices, start_end):
    """Return the index of the slice that contains a given slice, or -1."""
    from bisect import bisect_right
    slice_r = bisect_right(slices, start_end)
    start, end = start_end
    if slice_r > 0:
        (l, r) = slices[slice_r - 1]
        if l <= start and end <= r:
            return slice_r - 1
    if slice_r < len(slices):
        (l, r) = slices[slice_r]
        if l <= start and end <= r:
            return slice_r
    return -1

def slices_remove(slices, start_end):
    """Remove a slice from a list of slices."""
    idx = slices_find(slices, start_end)
    start, end = start_end
    if idx < 0:
        raise KeyError("%s not found" % repr(start_end))

    if slices[idx] == (start, end):  # deleting an entire slice
        del slices[idx]
    elif slices[idx][0] == start:  # cutting the start of a slice
        slices[idx] = (end, slices[idx][1])
    elif slices[idx][1] == end:  # cutting the end of a slice
        slices[idx] = (slices[idx][0], start)
    else:  # cutting the middle out of a slice
        slices[idx:idx + 1] = [(slices[idx][0], start), (end, slices[idx][1])]

def ffd_find(prgbanks, datalen, bank_factory=None):
    """Find the first unused range that will accept a given piece of data.

prgbanks -- a list of (bytearray, slice list) tuples
datalen -- the length of a byte string to insert in an unused area
bank_factory -- a function returning (bytearray, slice list), called
    when data doesn't fit, or None to instead throw ValueError

We use the First Fit Decreasing algorithm, which has been proven no
more than 22% inefficient (Yue 1991).  Because we don't plan to
insert more than about 100 things into a ROM at once, we can deal
with O(n^2) time complexity and don't need the fancy data structures
that O(n log n) requires.  Yet.

Return a (bank, address) tuple denoting where it would be inserted.
"""

    for (bank, (prgdata, unused_ranges)) in enumerate(prgbanks):
        for (start, end) in unused_ranges:
            if start + datalen <= end:
                return (bank, start)

    # At this point we need to add another PRG bank.  Create a PRG
    # bank that has the reset patch built into it.
    if not bank_factory:
        raise ValueError("could not add bank")
        
    prgbanks.append(bank_factory())
    last_bank_ranges = prgbanks[-1][1]
    if datalen > last_bank_ranges[0][1] - last_bank_ranges[0][0]:
        raise ValueError("string too long")
    return (len(prgbanks) - 1, 0x8000)

def ffd_add(prgbanks, data, bank_factory=None):
    """Insert a string into a bank using FFD.

data -- the byte string to insert

Other arguments and return same as those for ffd_find.
"""
    from array import array

    (bank, address) = ffd_find(prgbanks, len(data), bank_factory)
    offset = address - 0x8000
    (romdata, unused_ranges) = prgbanks[bank]
    romdata[offset:offset + len(data)] = array('B', data)
    slices_remove(unused_ranges, (address, address + len(data)))
    return (bank, address)

