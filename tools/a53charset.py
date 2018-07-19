#!/usr/bin/env python3
import codecs

# The first 96 glyphs in the font correspond to the 96 printable code
# points of the Basic Latin (ASCII) block, U+0020 through U+007F.
# The rest are
name = 'action53'
extra_codepoints = [
    # A button, B button, copyright, d-pad
    0x24B6, 0x24B7, 0x00A9, 0x271C,
    # up arrow, down arrow, left arrow, right arrow
    0x2191, 0x2193, 0x2190, 0x2192,
    # L with stroke, z with dot, e with tail, 1 px space
    0x0141, 0x017C, 0x0119, 0x2423,
    # bird
    0x1F426
]

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

### Translate the decoding

decoding_table = list(range(128))
decoding_table.extend(extra_codepoints)
decoding_table.extend([0xFFFE] * (256 - len(decoding_table)))
decoding_table = ''.join(chr(x) for x in decoding_table)
encoding_table=codecs.charmap_build(decoding_table)

### Testing

def main():
    register()
    s = "HELŁO"
    b = s.encode(name)
    print(s)
    print(b.hex())

if __name__=='__main__':
    main()
