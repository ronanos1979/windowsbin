#!/bin/sh


find . -iname \*JPG -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*JPEG -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*jpg -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*jpeg -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*heic -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*HEIC -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*mp4 -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*MP4 -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*MOV -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*mov -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*png -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;
find . -iname \*PNG -exec exiv2 -v -t -r '%Y%m%d_%H%M%S_:basename:' rename {} \;



#for file in `ls`
#do
# echo "Current file is $file"
 
 
# a_value=`$(identify -format "%[EXIF:DateTime]" $file | grep unknown)`
# echo ronan says $a_value
 
 #if [ $(identify -format "%[EXIF:DateTime]" $file | grep unknown) ]; then
#	echo "0"
#else 
		#echo "1"
    
#fi
	#typeset ret_code
	#ret_code=$?
	#if [ $ret_code == 0 ]; then
	#	echo "ret_code is 0"
	#else
#		echo "else"

#	fi
#done
