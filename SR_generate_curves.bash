#!/bin/bash

VID_1080_MAIN_DIR=/opt/a/shared/movies_1080/Test
VID_540_MAIN_DIR=/opt/a/shared/movies_540/Test
VID_1080_DIR=./movies_1080
VID_540_DIR=./movies_540
VID_SR_DIR=./movies_SR
RES_DIR=./experiment_results



TMP_DIR=./temp_dir
DUMMY_FILE=${TMP_DIR}/dummy

LR_PNG_DIR=${TMP_DIR}/LR_png
SR_PNG_DIR=${TMP_DIR}/SR_png
HR_PNG_DIR=${TMP_DIR}/HR_png

conda activate conda36

echo "Resetting the results. Delete previous outputs?"
rm -ri $RES_DIR/*

if [ ! -d $TMP_DIR ]; then
	mkdir $TMP_DIR
	mkdir $LR_PNG_DIR
	mkdir $SR_PNG_DIR
	mkdir $HR_PNG_DIR
else
	rm -rf $TMP_DIR/*
	mkdir $SR_PNG_DIR
	mkdir $LR_PNG_DIR
	mkdir $HR_PNG_DIR
fi


if [ ! -d $RES_DIR ]; then
	mkdir $RES_DIR
fi

for trimmer in {00..50..10}
do
	for f_full in $VID_1080_MAIN_DIR/*.mov
	do
		rm $VID_1080_DIR/* 
		rm $VID_540_DIR/*

		fname_ext_full=$(basename -- "$f_full")
		ext="${fname_ext_full##*.}"
		fname_full="${fname_ext_full%.*}"
		
		echo "Started working on $fname_full"	

		echo "Trimming 1080 video (Ground Truth)"
		fname=${fname_full}_$trimmer
		f_1080=$VID_1080_DIR/$fname.$ext
		ffmpeg -ss 00:00:$trimmer.000 -i $f_full -t 00:00:10.000 -c copy $f_1080 2>&-
		
		echo "Trimming 540 video (Low-Resolution)"
		f_540_full=$VID_540_MAIN_DIR/$fname_full.$ext
		f_540=$VID_540_DIR/$fname.$ext
		ffmpeg -ss 00:00:$trimmer.000 -i $f_540_full -t 00:00:10.000 -c copy $f_540 2>&-
		
		# Start Encode-Decode Process:
		for qp in {1..51..2}
		do
			echo "Encoding $fname_full, segment $(( $trimmer/10+1 ))/6 with QP=$qp..."
			# Encode
			f_540_enc=${TMP_DIR}/${fname}_540_enc_${qp}.$ext	
			ENCODED_SIZE=$(ffmpeg -i $f_540 -c:v libx264 -qp $qp -y $f_540_enc 2>&1 | grep -Po '(?<=video:)[^k]*') 
			# Decode
			
			echo "Decoding..."
			f_540_dec=${TMP_DIR}/${fname}_540_dec_${qp}.$ext		
			ffmpeg -i $f_540_enc -c:v v210 -y $f_540_dec 2>&-
			rm -f $f_540_enc
			
			# Reconstruct - Super Resolution
			f_540_rec=${TMP_DIR}/${fname}_540_rec_${qp}.mov
			
			echo "Extracting Frames..."
			ffmpeg -i $f_540_dec $LR_PNG_DIR/${fname_full}_%04d.bmp 2>&-
			ffmpeg -i $f_1080 $HR_PNG_DIR/${fname_full}_%04d.bmp 2>&-
			rm -f $f_540_dec
			
			echo "Running Super-Resolution..."
			ret_dir=$(pwd)
			conda activate condaSR
			cd ~/shared/subpixel-photo-code-v3/
			python main.py --test True --train False 2>&-
			conda activate conda36
			cd $ret_dir
			
			rm $LR_PNG_DIR/*
			rm $HR_PNG_DIR/*
			
			
			echo "Converting SR frames to video..."
			ffmpeg -framerate 60 -i $SR_PNG_DIR/${fname_full}_%04d.bmp -c:v v210 -y $f_540_rec 2>&-
			rm $SR_PNG_DIR/*
			
			
			#Calc and save PSNR
			echo "Evaluating the output - PSNR calculation..."
			RES_FILE=${RES_DIR}/PSNR_SR_540.txt
			PSNR=$(ffmpeg -i $f_540_rec -i $f_1080 -filter_complex "[1][0]psnr" -f null - 2>&1 | grep -Po '(?<=average:)[^ ]*')
			echo "$fname, $qp, $ENCODED_SIZE, $PSNR" >> $RES_FILE
			
			#read -p "Press [Enter] key to resume..."
			#clean up
			rm -rf $TMP_DIR/*
			mkdir $SR_PNG_DIR
			mkdir $LR_PNG_DIR
			mkdir $HR_PNG_DIR
		done
	done
done


