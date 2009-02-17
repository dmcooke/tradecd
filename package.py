#!/usr/bin/env python
import sys
import os
import zipfile

def read_toc(toc):
    fo = open(toc, 'r')
    d = {}
    files = []
    for line in fo:
        line = line.strip()
        if line.startswith('##'):
            k, v = line.lstrip('#').strip().split(':', 1)
            d[k.lower()] = v.strip()
        elif line and not line.startswith('#'):
            files.append(line)
    return d, files

def main(argv):
    toc = argv[1]
    d, files = read_toc(toc)
    addon, _ = os.path.splitext(os.path.basename(toc))
    z = zipfile.ZipFile(addon + '-' + d['version'] + '.zip', 'w')
    z.write(toc, addon + '/' + toc)
    for f in files:
        z.write(f, addon + '/' + f)
    z.close()
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))

