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
printf "Try authentication \n"

access_token=$(curl -s -X POST \
https://ws.api.video/token \
-H 'Content-Type: application/json' \
-d '{
    "username": "'${username}'",
    "password": "'${password}'"
}' | python -c 'import sys, json; print json.load(sys.stdin)["access_token"]')

if [ -z "$access_token" ];
then
    printf "Authentification failed. Please retry. \n"
    exit 1
fi

printf "Authentication succeed \n"

printf "Try create video from file %s \n" ${file}
source=$(curl -s -X POST \
    https://ws.api.video/videos \
    -H 'Content-Type: application/json' \
    -H 'Authorization: Bearer '${access_token} \
    -d $(printf '{"title":"%s"}' ${title}) |  python -c 'import sys, json; print json.load(sys.stdin)["source"]["uri"]'
)

if [ -z "$source" ];
then
    printf "Error when attempted to create video. Please retry. \n"
    exit 1
fi

printf "Create video succeed \n"


printf "Create chunk directory \n"
rm -rf /tmp/.apivideo-chunks
mkdir /tmp/.apivideo-chunks

printf "Split video into multiple chunks \n"
split -b 104857600 ${file} /tmp/.apivideo-chunks/chunk
filesize=$(wc -c ${file} | awk '{print $1}')

printf "File size %d \n" ${filesize}
numberChunks=$(ls -1 /tmp/.apivideo-chunks/chunk* 2>/dev/null | wc -l)
counter=0;
bytessend=0

printf "Try uploading %d chunks to https://ws.api.video%s \n\n" ${numberChunks} ${source}
for filename in /tmp/.apivideo-chunks/chunk*; do
    printf "* %s \n" ${filename}

    chunksize=$(wc -c ${filename} | awk '{print $1}')

    printf "  Chunk %d/%d size is %db \n" $((counter + 1)) ${numberChunks} ${chunksize}

    from=${bytessend}
    bytessend=$(($bytessend + $chunksize))

    printf "  Send bytes %d-%d/%d \n\n" ${from} $((bytessend - 1)) ${filesize}

    ((counter++))
    if [ ${counter} -eq ${numberChunks} ];
    then
        hls=$(curl -s  -X POST \
        https://ws.api.video${source} \
        -H 'Content-Range: bytes '${from}'-'$((bytessend - 1))'/'${filesize} \
        -H 'content-type: multipart/form-data;' \
        -H 'Authorization: Bearer '${access_token} \
        -F file=@${filename}  | python -c 'import sys, json; print json.load(sys.stdin)["assets"]["hls"]'
        )
        if [ -z "hls" ];
        then
            printf "Upload failed. Please retry \n"
            exit 1
        fi
        printf "Get HLS stream from %s \n" ${hls}

    else
        curl -s -X POST \
        https://ws.api.video${source} \
        -H 'Content-Range: bytes '${from}'-'$((bytessend - 1))'/'${filesize}'' \
        -H 'Expect: 100-Continue' \
        -H 'content-type: multipart/form-data;' \
        -H 'Authorization: Bearer '${access_token} \
        -F file=@${filename}
    fi

done
