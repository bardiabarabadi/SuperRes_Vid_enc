#!/bin/bash

VID_1080_MAIN_DIR=/opt/a/shared/movies_1080/
VID_1080_DIR=./movies_1080/;
VID_720_DIR=./movies_720/;
VID_540_DIR=./movies_540/;
RES_DIR=./experiment_results/;


TMP_DIR=./temp_dir/;
DUMMY_FILE=${TMP_DIR}dummy


echo "Resetting the results. Delete previous outputs?"
rm -i $RES_DIR*

if [ ! -d $TMP_DIR ]; then
	mkdir $TMP_DIR
else
	rm -rf ${TMP_DIR}*
fi


if [ ! -d $RES_DIR ]; then
	mkdir $RES_DIR
fi
for trimmer in {00..50..10}
do
	for f_full in $VID_1080_MAIN_DIR*.mov
	do
		rm -f $VID_1080_DIR* $VID_720_DIR* $VID_540_DIR*

		fname_ext_full=$(basename -- "$f_full")
		ext="${fname_ext_full##*.}"
		fname_full="${fname_ext_full%.*}"
		
		echo "Started working on $fname_full"	


		fname=${fname_full}_$trimmer
		f=$VID_1080_DIR$fname.$ext
		ffmpeg -ss 00:00:$trimmer.000 -i $f_full -t 00:00:10.000 -c copy $f 2>&-
		echo "Trimmed version generated at $f"

		f_720=${VID_720_DIR}${fname}.$ext
		f_540=${VID_540_DIR}${fname}.$ext


		
		# f_720 = convert_lossless (f, 720)
		ffmpeg -i $f -vf scale=1280x720 -c:v v210 -y $f_720 2>&-

		# f_540 = convert_lossless (f, 540)
		ffmpeg -i $f -vf scale=960x540 -c:v v210 -y $f_540 2>&-


		# Start Encode-Decode Process:
		for qp in {1..51..2}
		do
			## Curve #1
			# Encode
			f_1080_enc=${TMP_DIR}${fname}_1080_enc_${qp}.mp4	
			ENCODED_SIZE=$(ffmpeg -i $f -c:v libx264 -qp $qp -y $f_1080_enc 2>&1 | grep -Po '(?<=video:)[^k]*') 
			# Decode
			f_1080_rec=${TMP_DIR}${fname}_1080_rec_${qp}.mov		
			ffmpeg -i $f_1080_enc -c:v v210 -y $f_1080_rec 2>&-
			
			#Calc and save PSNR
			RES_FILE=./${RES_DIR}PSNR_1080.txt
			PSNR=$(ffmpeg -i $f_1080_rec -i $f -filter_complex "[1][0]psnr" -f null - 2>&1 | grep -Po '(?<=average:)[^ ]*')

			echo "$fname, $qp, $ENCODED_SIZE, $PSNR" >> $RES_FILE
			#clean up
			rm -f $TMP_DIR* *.csv

		#--------------------------------------------------------------------------------------------------------------------------------------------

			## Curve #2
			# Encode
			f_720_enc=${TMP_DIR}${fname}_720_enc_${qp}.$ext	
			ENCODED_SIZE=$(ffmpeg -i $f_720 -c:v libx264 -qp $qp -y $f_720_enc 2>&1 | grep -Po '(?<=video:)[^k]*') 
			# Decode
			f_720_dec=${TMP_DIR}${fname}_720_dec_${qp}.$ext		
			ffmpeg -i $f_720_enc -c:v v210 -y $f_720_dec 2>&-

			# Reconstruct
			f_720_rec=${TMP_DIR}${fname}_720_rec_${qp}.mov
			ffmpeg -i $f_720_dec -vf scale=1920x1080 -c:v v210 $f_720_rec 2>&-
			
			#Calc and save PSNR
			RES_FILE=./${RES_DIR}PSNR_720.txt

			PSNR=$(ffmpeg -i $f_720_rec -i $f -filter_complex "[1][0]psnr" -f null - 2>&1 | grep -Po '(?<=average:)[^ ]*')		
			
			echo "$fname, $qp, $ENCODED_SIZE, $PSNR" >> $RES_FILE
			
			#clean up
			rm -f $TMP_DIR* *.csv

		#--------------------------------------------------------------------------------------------------------------------------------------------

			## Curve #3
			# Encode
			f_540_enc=${TMP_DIR}${fname}_540_enc_${qp}.$ext	
			ENCODED_SIZE=$(ffmpeg -i $f_540 -c:v libx264 -qp $qp -y $f_540_enc 2>&1 | grep -Po '(?<=video:)[^k]*') 
			# Decode
			f_540_dec=${TMP_DIR}${fname}_540_dec_${qp}.$ext		
			ffmpeg -i $f_540_enc -c:v v210 -y $f_540_dec 2>&-

			# Reconstruct
			f_540_rec=${TMP_DIR}${fname}_540_rec_${qp}.mov
			ffmpeg -i $f_540_dec -vf scale=1920x1080 -c:v v210 $f_540_rec 2>&-
			
			#Calc and save PSNR
			RES_FILE=./${RES_DIR}PSNR_540.txt
			
			PSNR=$(ffmpeg -i $f_540_rec -i $f -filter_complex "[1][0]psnr" -f null - 2>&1 | grep -Po '(?<=average:)[^ ]*')
			echo "$fname, $qp, $ENCODED_SIZE, $PSNR" >> $RES_FILE
			#clean up
			rm -f $TMP_DIR* *.csv

		done
	done
done

