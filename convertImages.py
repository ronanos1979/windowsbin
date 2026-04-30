import glob
import os
import sys
import subprocess

# subprocess.Popen(cmd, stderr=subprocess.STDOUT, stdout=subprocess.PIPE)

path = '/mnt/d/Newfolder/'
files = os.listdir(path)

print ('Ronan says path is ', path)
for imageFile in files: 
    # if files[-4:] != ".jpg"
    #   continue
    if imageFile.endswith(".JPEG"):    
        print ('Ronan says file is: ' + imageFile)
        cmdLine = ['ls', imageFile]
        
            #from subprocess impor Popen,PIPE

       # p = subprocess.Popen(["ls","-al"],stdout=subprocess.PIPE)

        #stderr = p.communicate()

        #print(stderr)
        
        #cmdLine = ['identify', ' -format "%[EXIF:DateTime]" ', imageFile]
        #subprocess.Popen(args=['ls', '-l'], returncode=0)
        #output1 = subprocess.Popen(cmdLine, stdout=subprocess.PIPE).communicate()[0]
        #print (output1)    
        cmdLine = ["identify", "-format \"%[EXIF:DateTime]\" " + imageFile]
        output2 = subprocess.Popen(['ls', 'IMG_4581.JPEG'], stdout=subprocess.PIPE).communicate()[0]
        print ('Value is: ', output2)
        #output2 = subprocess.Popen(['ls -ltr', imageFile], stdout=subprocess.PIPE).communicate()[0]
        #print (output2)
        
        
files = os.listdir('/input')
for sourceVideo in files:
    if sourceVideo[-4:] != ".avi"
        continue
    destinationVideo = sourceVideo[:-4] + ".mpg"
    cmdLine = ['mencoder', sourceVideo, '-ovc', 'copy', '-oac', 'copy', '-ss',
        '00:02:54', '-endpos', '00:00:54', '-o', destinationVideo]
    output1 = Popen(cmdLine, stdout=PIPE).communicate()[0]
    print output1
    output2 = Popen(['del', sourceVideo], stdout=PIPE).communicate()[0]
    print output2        