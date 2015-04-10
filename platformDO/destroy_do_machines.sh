#!/bin/bash

# This stops multiple coreos instances using digital ocean cloud platform
#
# Prerequisites:
# The following environment variables are used:
#   TOKEN  : digital ocean api-token (as environment variable)
#
# Optional prerequisites:
#   OUTPUT : local output log folder (e.g. -d my-directory)

#set -e
set -u

OUTPUT="digital_ocean"

while getopts ":d:" opt; do
  case $opt in
    d)
      OUTPUT="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

if [ ! -e "$OUTPUT" ] ;  then
  echo "$0: directory '$OUTPUT' not found"
  exit 1
fi

. $OUTPUT/clusterinfo.sh

declare -a SERVERS_IDS=(${SERVERS_IDS[@]})

NUMBER=${#SERVERS_IDS[@]}

echo "NUMBER OF MACHINES: $NUMBER"
echo "OUTPUT DIRECTORY: $OUTPUT"
echo "MACHINE PREFIX: $PREFIX"

if test -z "$TOKEN";  then
  echo "$0: you must supply a token as environment variable with 'export TOKEN='your_token''"
  exit 1
fi

wait

export CLOUDSDK_CONFIG="$OUTPUT/digital_ocean"
touch $OUTPUT/hosts
touch $OUTPUT/curl.log
CURL=""

function deleteMachine () {
  echo "deleting machine $PREFIX$1"
  id=${SERVERS_IDS[`expr $1 - 1`]}

  CURL=`curl --request DELETE "https://api.digitalocean.com/v2/droplets/$id" \
       --header "Content-Type: application/json" \
       --header "Authorization: Bearer $TOKEN" 2>/dev/null`
}

for i in `seq $NUMBER`; do
  deleteMachine $i &
done

wait

