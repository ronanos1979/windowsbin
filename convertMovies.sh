#!/bin/sh


# E.g. 100_0785.mov -> 20060101-025736-000-100_0785.mov
#
# -Comment -> Original name file. E.g. 100_0785.mov
# -UserComment -> Original name file. 100_0785.mov
#
# -DateTimeOriginal -> Get data from CreateDate. The standard EXIF date/time format is "YYYY:mm:dd HH:MM:SS". E.g 2013:07:13 12:30:45

exiftool -m -p -a -r -d %Y%m%d-%H%M%S -overwrite_original -if '(not $datetimeoriginal or $datetimeoriginal eq "0000:00:00 00:00:00") and ($createdate) and ($createdate ne "0000:00:00 00:00:00")' '-Comment<FileName' '-UserComment<FileName' '-datetimeoriginal<createdate' '-filename<${createdate}-000-${FileName;}%-c' .
