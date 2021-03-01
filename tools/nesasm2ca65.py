#!/usr/bin/env python3
"""

NESASM to ca65 syntax translator

Copyright 2012, 2020 Damian Yerrick
[insert zlib license here]

This tool covers just enough of NESASM's syntax to translate
LAN Master from NESASM to ca65 for inclusion in a submulti.

"""

import sys
import re

# Ordinarily we call the vectors segment "VECTORS", but we change it
# if we want the submulti shell to override a game's vectors.
# In LAN Master + Munchie Attack, we're discarding bank 4 because
# we're mapper hacking LAN Master to CHR RAM.
vectors_segment = "BANK4"
globals_line = '.global NMI_CALL, reset'

# these are applied only to the first word after the label if any
opcode_translation = {
    'equ': '=',
    '.db': '.byte',
    '.list': '.list on',
    '.nolist': '.list off',
    '.endm': '.endmacro',
    '.dw': '.addr',
    '.ds': '.res',
    '.org': ';.org',
    '.zp': '.zeropage',
    '.fail': '.assert 0, error, ".fail"',
    '.inesprg': ';.inesprg',
    '.ineschr': ';.ineschr',
    '.inesmir': ';.inesmir',
    '.inesmap': ';.inesmap',
}

words_translation = {
    # reference: https://cc65.github.io/doc/ca65.html
    # reference: https://raw.githubusercontent.com/camsaul/nesasm/master/usage.txt
    'low': '.lobyte',
    'high': '.hibyte',
    'bank': '<.bank',
    '[': '(',  # NESASM's syntax for (d),Y and (d,X)
    ']': ')',  # addressing modes is nonstandard
}

# Obscurities such as .func, .macro arguments, .incchr, .defchr, etc.
# are not translated.

words_nonwordsRE = re.compile(r"[$%.0-9a-zA-Z_]+|[^$%.0-9a-zA-Z_]")

def translate_word(word):
##    print(";translating %s" % word)
    word = words_translation.get(word.lower(), word)
    if word.startswith('.'):
        word = '@' + word[1:]
    return word

def translate_line(line):
    line_comment = line.split(';', 1)
    comment = line_comment[1] if len(line_comment) > 1 else ''
    line = line_comment[0].rstrip()
    if line == '':
        return ''

    # Apparently a label MUST begin in the first column,
    # and an instruction MUST NOT.
    splitParts = line.split()
    if not line[0].isspace():
        label = splitParts[0]
        if label.startswith('.'):
            label = '@' + label[1:]
        splitParts = splitParts[1:]
    else:
        label = ''
    if len(splitParts) > 0:
        opcode = splitParts[0]
        splitParts = splitParts[1:]
    else:
        opcode = ''

    # translate .db into .byt, etc.
    opcode = opcode_translation.get(opcode.lower(), opcode)

    # ca65 puts a colon after each label that's not part of an equate
    if label != '' and opcode != '=':
        label = label + ':'

    # ca65 uses link scripts
    if opcode == '.bank' and len(splitParts) == 1:
        opcode = '.segment'
        splitParts = ['"BANK%s"' % splitParts[0]]
    elif (opcode == ';.org' and len(splitParts) == 1
          and splitParts[0].lower() == '$fffa'):
        opcode = '.segment'
        splitParts = ['"%s"' % vectors_segment]

    splitParts = [''.join(translate_word(word)
                          for word in words_nonwordsRE.findall(part))
                  for part in splitParts]

    return "%s %s %s" % (label, opcode, ' '.join(splitParts))

def main():
    printed_globals_line = False
    # sys.stdin of IDLE in Python 2.6 wasn't iterable.
    # Fortunately, this was fixed by Python 3.6.
    for line in sys.stdin:
        line = translate_line(line)
        if line == '' and not printed_globals_line:
            line = globals_line
            printed_globals_line = True
        sys.stdout.write(line + "\n")

    # The globals line should have replaced an existing blank line.
    # (This is done to preserve source line numbers.)  If there was
    # no blank line, drop it here.
    if globals_line and not printed_globals_line:
        sys.stdout.write(globals_line + "\n")

if __name__=='__main__':
    main()
