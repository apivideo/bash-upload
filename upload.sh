#!/usr/bin/env bash
usage() { echo "Usage: $0 [-f <PATH_FILE>]" 1>&2; exit 1; }
debug=false
while getopts ":f:debug:" opt; do
    case "${opt}" in
        f)
            file=${OPTARG}
            ;;
        debug)
            debug=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))


if [ -z "${file}" ]; then
    usage
fi


read -p "Username:" username
printf "\n"
read -s -p "Password:" password
printf "\n"
read -p "Video title:" title

printf "\n"
printf "Try authentication"
printf "\n"

access_token=$(curl -X POST \
https://ws.api.video/token \
-H 'Content-Type: application/json' \
-d '{
    "username": "'${username}'",
    "password": "'${password}'"
}' | python -c 'import sys, json; print json.load(sys.stdin)["access_token"]')

if [ -z "$access_token" ];
then
    printf "Authentification failed. Please retry."
    printf "\n"
    exit 1
fi

printf "Authentication succeed"
printf "\n"
printf "Try create video"
printf "\n"
printf "From file "${file}
printf "\n"
printf "curl -v -X POST \
https://ws.api.video/videos \
-H 'Content-Type: application/json' \
-H 'Authorization: Bearer '${access_token} \
-d '{\"title\":\"${title}\"}'"

source=$(curl -X POST \
https://ws.api.video/videos \
-H 'Content-Type: application/json' \
-H 'Authorization: Bearer '${access_token} \
-d '{"title":"${title}"}' | python -c 'import sys, json; print json.load(sys.stdin)["source"]["uri"]')


if [ -z "$source" ];
then
    printf "Error when attempted to create vidéo. Please retry."
    printf "\n"
    exit 1
fi

printf ${source}
printf "\n"

printf "Create video succeed"
printf "\n"


printf "Create chunk directory"
printf "\n"

rm -rf ./videoChunk
mkdir ./videoChunk



printf "Split video into multiple chunks"
printf "\n"

split --bytes=100M ${file} ./videoChunk/videoChunked


filesize=$(wc -c ${file} | awk '{print $1}')


printf "File size "${filesize}
printf "\n"

numberChunks=$(($(ls -l ./videoChunk | grep -v ^d | wc -l)-1))

counter=0;
bytessend=0
printf "Try uploading to https://ws.api.video"${source}
printf "\n"

for filename in ./videoChunk/*; do
    printf "\n"
    printf ${filename}
    printf "\n"
    fullpath=$(find $(pwd)/${filename} -type f)
    printf ${fullpath}
    printf "\n"

    chunksize=$(wc -c ${filename} | awk '{print $1}')

    printf "Chunk size is "${chunksize}
    printf "\n"
    printf "Bytes send is "${bytessend}
    printf "\n"

    from=${bytessend}
    bytessend=$(($bytessend + $chunksize))

    printf "Send bytes "${from}"-"$((bytessend - 1))"/"${filesize}
    printf "\n"




    ((counter++))
    if [ ${counter} -eq ${numberChunks} ];
    then
        hls=$(curl -X POST \
        https://ws.api.video${source} \
        -H 'Content-Range: bytes '${from}'-'$((bytessend - 1))'/'${filesize} \
        -H 'content-type: multipart/form-data;' \
        -H 'Authorization: Bearer '${access_token} \
        -F file=@${fullpath}  | python -c 'import sys, json; print json.load(sys.stdin)["assets"]["hls"]'
        )
        if [ -z "hls" ];
        then
            printf "Upload failed. Please retry"
            printf "\n"
            exit 1
        fi
        printf "Get HLS stream from "${hls}
        printf "\n"
    else
        curl -X POST \
        https://ws.api.video${source} \
        -H 'Content-Range: bytes '${from}'-'$((bytessend - 1))'/'${filesize}'' \
        -H 'Expect: 100-Continue' \
        -H 'content-type: multipart/form-data;' \
        -H 'Authorization: Bearer '${access_token} \
        -F file=@${fullpath}
    fi

done
