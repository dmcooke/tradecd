#!/usr/bin/env python
import sys
import os
import glob
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
    if len(argv) < 2:
        tocs = glob.glob('*.toc')
        if len(tocs) != 1:
            print "Can't figure out what .toc file to use; please specify"
            return 1
        toc = tocs[0]
    else:
        toc = argv[1]
    if not toc.endswith('.toc'):
        print "Specified .toc file should end in .toc"
        return 1
    d, files = read_toc(toc)
    addon, _ = os.path.splitext(os.path.basename(toc))
    z = zipfile.ZipFile(addon + '-' + d['version'] + '.zip', 'w')
    z.write(toc, addon + '/' + toc)
    if d['x-extrafiles']:
        extra = d['x-extrafiles'].split()
        files.extend(extra)
    for f in files:
        z.write(f, addon + '/' + f)
    z.close()
    return 0

if __name__ == '__main__':
    sys.exit(main(sys.argv))

