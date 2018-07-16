#!/usr/bin/env python3

class InnieParser(object):
    r"""

The data format is similar but not identical to Microsoft INI or
ConfigParser.RawConfigParser format.

name=value
other=something
multiline:
Using a colon instead of an equals sign begins a multi-line
value.  A period on its own line ends it.
.
dot warning:
As with SMTP, the first period on any other line is removed.
So any line starting with a dot should have this dot escaped
.... like this.  (Four periods become three.)
.
duplicates=Multiple values with the same name are allowed.
duplicates=Some apps may interpret this as a command to start a section.
# A line starting with # or ; outside a multiline produces a comment.
# Comments are treated as values with the name '#' or ';'
# so that they can be round-tripped.

blank value=
name rule=Names may not begin or end with whitespace.
name rule = Nor may they begin
NAME RULE = By default, are case-insensitive.

"""
    import re as _re

    _firstlineRE = _re.compile('\s*([^;#[][^=:]*[=:]|[;#])\s*(.*)')
    _secttitleRE = _re.compile('\s*(\[)\s*([^]]+?)\s*\]\s*')

    def __init__(self, data=None, filenames=None):
        self.pair_filters = []
        self.pairs = []
        self.cur_path = None
        if data:
            self.readstring(data)
        if filenames:
            ok = self.read(filenames)

    def clear(self):
        self.pairs = []

    def optionxform(self, name):
        """Processes a name before sending it to the pair filter change.

The default implementation changes the name to lower case.
Subclasses may override this.

"""
        return name.lower()

    def addfilter(self, new_filter):
        """Adds a pair filter to the end of the filter chain.

A pair filter is a function, called as f(name, value), and returns
either a (name, value) tuple or None.  If None is returned, the
line is not added, and no further filters are called.  If a pair is
returned, it is passed on to the next filter.  If the last filter
returns a pair, add it to the list.

"""
        self.pair_filters.append(new_filter)

    def addfilteredpair(self, k, v):
        k = self.optionxform(k.rstrip())
        for f in self.pair_filters:
            values = f(k, v)
            if not values:
                return
            (k, v) = values
        self.pairs.append((k, v))

    def close_multiline(self):
        """Close a multiline comment."""
        if len(self.pairs) > 0 and isinstance(self.pairs[-1][1], list):
            (k, v) = self.pairs.pop()
            v = "\n".join(v)
            self.addfilteredpair(k, v)

    def addline(self, s):
        """Parse and add a single line of text."""
        s = s.rstrip('\r\n')
        if len(self.pairs) > 0 and isinstance(self.pairs[-1][1], list):
            if s == '.':
                self.close_multiline()
                return

            # Initial periods are escaped with a period as in SMTP
            if s.startswith('.'):
                s = s[1:]
            self.pairs[-1][1].append(s)
            return

        # at this point we're not in a multiline
        s = s.lstrip()
        if not s:
            return
        m = self._firstlineRE.match(s) or self._secttitleRE.match(s)
        if m is None:
            raise ValueError("unrecognized pair: " + repr(s))
        (k, v) = m.groups()
        if k.endswith('='):
            k = k[:-1].rstrip()
        elif k.endswith(':'):
            k = k[:-1].rstrip()
            v = [v] if v else []
            self.pairs.append((k, v))
            return
        self.addfilteredpair(k, v)

    def readfp(self, infp):
        """Add pairs from an open file-like object.

infp must be a file or other object supporting iteration over lines.

"""
        for line in infp:
            self.addline(line)

    def readstring(self, s):
        """Add pairs from a string."""
        self.readfp(s.split('\n'))
        
    def read(self, filenames):
        """Attempt to read and parse one or more files.

filenames can be a list of paths or a str being a single path.
If a file cannot be read, it is ignored.  Otherwise, it is parsed
using readfp().  Returns a list of all files that were successfully
read.

"""
        if isinstance(filenames, str):
            filenames = [filenames]
        oknames = []
        for filename in filenames:
            self.cur_path = filename
            try:
                with open(filename, 'r', encoding="utf-8") as infp:
                    oknames.append(filename)
                    lines = list(infp)
            except OSError:
                pass
            else:
                oknames = []
                self.readfp(lines)
            finally:
                self.close_multiline()
        return oknames

# "Why don't you use ConfigParser.RawConfigParser?"
# No support for whitespace after a newline, which means no
# double spacing and no indentation.

testdata1 = """
name=value
other=something
duplicates=Multiple values with the same name are allowed.
duplicates=Some filters may interpret this as a command to start a section.
multiline:
Using a colon instead of an equals sign begins a multi-line
value.  A period on its own line ends it.
.
dot warning:
As with SMTP, the first period on any other line is removed.
So any line starting with a dot should have this dot escaped
.... like this.  (Four periods become three.)
.
# A line starting with # or ; outside a multiline produces a comment.
# Comments are treated as values with the name '#' or ';'
# so that they can be round-tripped.

blank value=
name rule=Names may not begin or end with whitespace.
name rule=Names may not begin with ';', '#', or '['.
name rule = Nor may they contain '=' or ':', but anything else is fair game.
NAME RULE = By default, names are case-insensitive; override optionxform to change this.
"""

def show_appends(k, v):
    item = (k, v)
    print("Appending %s" % repr(item))
    return item

if __name__ == '__main__':
    parser = InnieParser()
##    parser.addfilter(show_appends)
##    parser.readstring(testdata1)
##    print("\n".join(repr(r) for r in parser.pairs))
##    parser.clear()
    parser.read("roms.cfg")
    print("\n".join(repr(r) for r in parser.pairs))
