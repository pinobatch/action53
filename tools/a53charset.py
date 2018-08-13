#!/usr/bin/env python3
import codecs

# Make a special character codepage mapping starting from ASCII printable
# characters and adding special characters in non-whitespace ASCII control
# characters. So that 128 of the 256 available characters can be used
# for DTE code units.
name = 'action53'
decoding_table = [
    # Some ASCII control characters
    # 0x00 and 0x0a are for termination and newline respectively
    *range(16),
    # unassigned
    *[0xFFFE]*4,
    # copyright, L with stroke, z with dot, e with tail
    0x00A9, 0x0141, 0x017C, 0x0119,
    # A button, B button, d-pad, bird
    0x24B6, 0x24B7, 0x271C, 0x1F426,
    # up arrow, down arrow, left arrow, right arrow
    0x2191, 0x2193, 0x2190, 0x2192,
    # Ascii printable characters
    *range(32,127),
    # 1 px space, in the place of ASCII DEL
    0x2423,
    # reserved for DTE
    *[0xFFFE]*128,
]

### encoding map from decoding table

#encoding_table = codecs.charmap_build(''.join(chr(x) for x in decoding_table))
encoding_table = dict((c,i) for (i,c) in enumerate(decoding_table))

# Codecs API boilerplate ############################################

### Codec APIs

class Codec(codecs.Codec):

    def encode(self,input,errors='strict'):
        return codecs.charmap_encode(input,errors,encoding_table)

    def decode(self,input,errors='strict'):
        return codecs.charmap_decode(input,errors,decoding_table)

class IncrementalEncoder(codecs.IncrementalEncoder):
    def encode(self, input, final=False):
        return codecs.charmap_encode(input,self.errors,encoding_table)[0]

class IncrementalDecoder(codecs.IncrementalDecoder):
    def decode(self, input, final=False):
        return codecs.charmap_decode(input,self.errors,decoding_table)[0]

class StreamWriter(Codec,codecs.StreamWriter):
    pass

class StreamReader(Codec,codecs.StreamReader):
    pass

### encodings module API

def getregentry():
    return codecs.CodecInfo(
        name=name,
        encode=Codec().encode,
        decode=Codec().decode,
        incrementalencoder=IncrementalEncoder,
        incrementaldecoder=IncrementalDecoder,
        streamreader=StreamReader,
        streamwriter=StreamWriter,
    )

def register():
    ci = getregentry()
    def lookup(encoding):
        if encoding == name:
            return ci
    codecs.register(lookup)

# End boilerplate ###################################################

### Testing

def main():
    register()
    s = "HELŁO"
    b = s.encode(name)
    print(s)
    print(b.hex())

if __name__=='__main__':
    main()
