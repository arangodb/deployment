#!/bin/bash
# This removes all of your arangodb-test instances from digital ocean cloud platform
#
# Prerequisites:
# The following environment variables are used:
#   TOKEN  : digital ocean api-token (as environment variable)
#
# The following parameter is needed:
#   ARANGODB_ID: the id we had given your digital ocean instances. For examlpe if your
#                server instances are named like:
#
#                 - arangodb-test-39055-1
#                 - arangodb-test-39055-2
#                 - arangodb-test-39055-3
#
#                your ARANGODB_ID is 39055 (e.g. -i 39055)
#   OUTPUT: path to local output log folder (e.g. /my/directory)

set -u

: ${TOKEN?"You must supply a token as environment variable with 'export TOKEN='your_token'"}

ARANGODB_ID=""
OUTPUT="do_removal"

#COREOS PARAMS

while getopts ":i:" opt; do
  case $opt in
    i)
      ARANGODB_ID="$OPTARG"
      ;;
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

PREFIX="arangodb-test-$ARANGODB_ID-"
echo "MACHINES PREFIX: $PREFIX"

if test -z "$ARANGODB_ID";  then
  echo "$0: you must supply the ARANGODB_ID value with: -i 'your_arangodb_instances_id''"
  exit 1
fi

mkdir "$OUTPUT"

function deleteMachine () {
  curl -X DELETE -H 'Content-Type: application/json' \
       -H "Authorization: Bearer $TOKEN" "https://api.digitalocean.com/v2/droplets/$ID"
}

#GET DROPLETS
DROPLETS=`curl -s -X GET -H 'Content-Type: application/json' \
     -H "Authorization: Bearer $TOKEN" "https://api.digitalocean.com/v2/droplets"`

echo $DROPLETS | python -mjson.tool | grep "\"id\"" | awk '{print $2}' | rev | cut -c 2- | rev > $OUTPUT/ids

#loop through available arangodb instances
#for i in `seq $NUMBER`; do
#  deleteMachine $i &
#done
