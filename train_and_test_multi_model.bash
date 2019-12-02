#!/bin/bash

SECTION=Train

VID_1080_MAIN_DIR=/opt/a/shared/movies_1080
VID_540_MAIN_DIR=/opt/a/shared/movies_540

VID_1080_TEST_DIR=/opt/a/shared/movies_1080/Test
VID_540_TEST_DIR=/opt/a/shared/movies_540/Test


RES_DIR=./experiment_results

TMP_DIR_TRAIN=./temp_dir

TMP_DIR=~/CodedSR/temp_dir
LR_PNG_DIR=${TMP_DIR}/LR_png
SR_PNG_DIR=${TMP_DIR}/SR_png
HR_PNG_DIR=${TMP_DIR}/HR_png


VID_1080_DIR=$TMP_DIR/movies_1080
VID_540_DIR=$TMP_DIR/movies_540
VID_SR_DIR=$TMP_DIR/movies_SR

conda activate conda36


if [ ! -d $TMP_DIR_TRAIN ]; then
	mkdir $TMP_DIR_TRAIN
else
	rm -rf $TMP_DIR_TRAIN/*
fi


if [ ! -d $TMP_DIR ]; then
	mkdir $TMP_DIR
	mkdir $LR_PNG_DIR
	mkdir $SR_PNG_DIR
	mkdir $HR_PNG_DIR
	mkdir $VID_1080_DIR
	mkdir $VID_540_DIR
	mkdir $VID_SR_DIR
else
	rm -rf $TMP_DIR/*
	mkdir $SR_PNG_DIR
	mkdir $LR_PNG_DIR
	mkdir $HR_PNG_DIR
	mkdir $VID_1080_DIR
	mkdir $VID_540_DIR
	mkdir $VID_SR_DIR
fi


for qp in {51..1..2}
do

    # Start Encode-Decode Process:
    for f_full in $VID_1080_MAIN_DIR/*.mov
    do
            
                rm -rf $TMP_DIR/*
                fname_ext_full=$(basename -- "$f_full")
                ext="${fname_ext_full##*.}"
                fname="${fname_ext_full%.*}"
    
                echo "Started working on $fname"
        
                f_540=$VID_540_MAIN_DIR/$fname_ext_full
                f_1080=$f_full
        
        echo "Encoding $fname_full with QP=$qp..."
        # Encode
        f_540_enc=${TMP_DIR_TRAIN}/${fname}_540_enc_${qp}.$ext 	
        ENCODED_SIZE=$(ffmpeg -i $f_540 -c:v libx264 -qp $qp -y $f_540_enc 2>&1 | grep -Po '(?<=video:)[^k]*') 
        # Decode
        
        echo "Decoding..."
        f_540_dec=${TMP_DIR_TRAIN}/${fname}_540_dec_${qp}.$ext		
        ffmpeg -i $f_540_enc -c:v v210 -y $f_540_dec  2>&-
        rm -f $f_540_enc

        
        echo "Extracting Frames..."
        ffmpeg -i $f_540_dec ./dataset/$SECTION/frames_LR/${fname}_%04d.png  2>&-
        ffmpeg -i $f_1080 ./dataset/$SECTION/frames_HR/${fname}_%04d.png  2>&-
        rm -f $f_540_dec
        
    done
    
    echo "Training Super-Resolution..."
    ret_dir=$(pwd)
    conda activate condaSR
    cd subpixel-photo-code-v3/
    sed -i "s/qp = [0-9]*/qp = ${qp}/g" config.py
    python main.py --test False --train True 2>&-
    conda activate conda36
    cd $ret_dir
    
    rm ./dataset/$SECTION/frames_LR/*
    rm ./dataset/$SECTION/frames_HR/*

    # Testing Started
    echo "Testing the SR and evaluating PSNR for qp=$qp"
    for trimmer in {00..50..10}
    do
        for f_full_test in $VID_1080_TEST_DIR/*.mov
        do
            rm $VID_1080_DIR/* 
            rm $VID_540_DIR/*
            
            fname_ext_full=$(basename -- "$f_full_test")
            ext="${fname_ext_full##*.}"
            fname_full="${fname_ext_full%.*}"
        
            echo "Started testing $fname_full"	
            
            echo "Trimming 1080 video (Ground Truth)"
            fname=${fname_full}_$trimmer
            f_1080=$VID_1080_DIR/$fname.$ext
            ffmpeg -ss 00:00:$trimmer.000 -i $f_full_test -t 00:00:10.000 -c copy $f_1080 2>&-
            
            echo "Trimming 540 video (Low-Resolution)"
            f_540_full=$VID_540_TEST_DIR/$fname_full.$ext
            f_540=$VID_540_DIR/$fname.$ext
            ffmpeg -ss 00:00:$trimmer.000 -i $f_540_full -t 00:00:10.000 -c copy $f_540 2>&-
            echo "Encoding $fname_full, segment $(( $trimmer/10+1 ))/6"
            
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
			cd ./subpixel-photo-code-v3/
			python main.py --test True --train False 2>&-
			conda activate conda36
			cd $ret_dir
			
			rm $LR_PNG_DIR/*
			rm $HR_PNG_DIR/*
			
			echo "Converting SR frames to video..."
			ffmpeg -framerate 60 -i $SR_PNG_DIR/${fname_full}_%04d.bmp -c:v v210 -y $f_540_rec 2>&-
			rm $SR_PNG_DIR/*
            
            echo "Evaluating the output - PSNR calculation..."
			RES_FILE=${RES_DIR}/PSNR_SR_540.txt
			PSNR=$(ffmpeg -i $f_540_rec -i $f_1080 -filter_complex "[1][0]psnr" -f null - 2>&1 | grep -Po '(?<=average:)[^ ]*')
			echo "$fname, $qp, $ENCODED_SIZE, $PSNR" >> $RES_FILE
            echo "$fname, qp=$qp, fileSize=$ENCODED_SIZE, PSNR=$PSNR"
            
            #clean up
			rm -rf $TMP_DIR/*
			mkdir $SR_PNG_DIR
			mkdir $LR_PNG_DIR
			mkdir $HR_PNG_DIR
            mkdir $VID_1080_DIR
            mkdir $VID_540_DIR
            mkdir $VID_SR_DIR
        done
    done
done

