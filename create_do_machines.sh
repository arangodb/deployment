#!/bin/bash

# This starts multiple coreos instances using digital ocean cloud platform
#
# Prerequisites:
# The following environment variables are used:
#   TOKEN  : digital ocean api-token (as environment variable)
#
# Optional prerequisites:
#   REGION : size of the server (e.g. -z nyc3)
#   SIZE   : size/machine-type of the instance (e.g. -m 512mb)
#   NUMBER : count of machines to create (e.g. -n 3)
#   OUTPUT : local output log folder (e.g. -d my-directory)
#   SSHID  : id of your existing ssh keypair. if no id is set, a new
#            keypair will be generated and transfered to your created
#            instance (e.g. -s 123456)
#   PREFIX : prefix for your machine names (e.g. "export PREFIX="arangodb-test-$$-")

#set -e
set -u

REGION="sgp1"
SIZE="512mb"
NUMBER="3"
OUTPUT="digital_ocean"
IMAGE="coreos-stable"
SSHID=""

#COREOS PARAMS
declare -a SERVERS_EXTERNAL
declare -a SERVERS_INTERNAL
SSH_USER="arangodb"
SSH_CMD="ssh"
SSH_SUFFIX="--ssh-key-file $OUTPUT/ssh-key -l $SSH_USER"

while getopts ":z:m:n:d:s:" opt; do
  case $opt in
    z)
      REGION="$OPTARG"
      ;;
    m)
      SIZE="$OPTARG"
      ;;
    n)
      NUMBER="$OPTARG"
      ;;
    d)
      OUTPUT="$OPTARG"
      ;;
    s)
      SSHID="$OPTARG"
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

PREFIX="arangodb-test-$$-"

echo "REGION: $REGION"
echo "SIZE: $SIZE"
echo "NUMBER OF MACHINES: $NUMBER"
echo "OUTPUT DIRECTORY: $OUTPUT"
echo "MACHINE PREFIX: $PREFIX"

if test -z "$TOKEN";  then
  echo "$0: you must supply a token as environment variable with 'export TOKEN='your_token''"
  exit 1
fi

if test -e "$OUTPUT";  then
  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

mkdir "$OUTPUT"

if test -z "$SSHID";  then
  echo "$0: no ssh key-pair id given. creating a new ssh key-pair."

  #generate ssh key for later deploy
  echo Generating local ssh keypair.
  ssh-keygen -t dsa -f digital_ocean/ssh-key -C "arangodb@arangodb.com" -N ""
  SSHPUB=`cat digital_ocean/ssh-key.pub`

  echo Deploying ssh keypair on digital ocean.
  SSHID=`curl -X POST -H 'Content-Type: application/json' \
       -H "Authorization: Bearer $TOKEN" \
       -d "{\"name\":\"arangodb\",\"public_key\":\"$SSHPUB\"}" "https://api.digitalocean.com/v2/account/keys" \
       | python -mjson.tool | grep "\"id\"" | awk '{print $2}' | rev | cut -c 2- | rev`

fi

export CLOUDSDK_CONFIG="$OUTPUT/digital_ocean"
touch $OUTPUT/hosts
touch $OUTPUT/curl.log
CURL=""

function createMachine () {
  echo "creating machine $PREFIX$1"

  CURL=`curl --request POST "https://api.digitalocean.com/v2/droplets" \
       --header "Content-Type: application/json" \
       --header "Authorization: Bearer $TOKEN" \
       --data "{\"region\":\"$REGION\", \"image\":\"$IMAGE\", \"size\":\"$SIZE\", \"name\":\"$PREFIX$1\",
         \"ssh_keys\":[\"$SSHID\"], \"private_networking\":\"true\" ,\"user_data\": \"\"}"`

  #save all IDs for fetching their detailed information


  to_file=`echo $CURL | python -mjson.tool | grep "\"id\"" | head -n 1 | awk '{print $2}' | rev | cut -c 2- | rev`
  echo $to_file > "$OUTPUT/temp/INSTANCEID$1"
}

function getMachine () {
  id=`cat $OUTPUT/temp/INSTANCEID$i`

  echo "fetching machine information from $PREFIX$1"
  RESULT2=`curl -X GET -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
                          "https://api.digitalocean.com/v2/droplets/$id"`

  a=`echo $RESULT2 | python -mjson.tool | grep "\"ip_address\"" | head -n 1 | awk '{print $2}' | cut -c 2- | rev | cut -c 3- | rev`
  b=`echo $RESULT2 | python -mjson.tool | grep "\"ip_address\"" | head -n 2 | tail -1 |awk '{print $2}' | cut -c 2- | rev | cut -c 3- | rev`

  echo $a > "$OUTPUT/temp/INTERNAL$1"
  echo $b > "$OUTPUT/temp/EXTERNAL$1"
}

mkdir "$OUTPUT/temp"

for i in `seq $NUMBER`; do
  createMachine $i &
done

wait

#Wait until machines are ready.
while :
do
   firstid=`cat $OUTPUT/temp/INSTANCEID$i`
   RESULT=`curl -X GET -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
                   "https://api.digitalocean.com/v2/droplets/$firstid"`
   CHECK=`echo $RESULT | python -mjson.tool | grep "\"id\"" | head -n 1 | awk '{print $2}' | rev | cut -c 2- | rev`

   if [ "$CHECK" != "not_found" ];
   then
     echo ready: droplets now online. now installing arangodb.
     break;
   else
     echo waiting: droplets not ready yet...
   fi

done

wait

sleep 5

for i in `seq $NUMBER`; do
  getMachine $i &
done

wait

for i in `seq $NUMBER`; do
  a=`cat $OUTPUT/temp/INTERNAL$i`
  b=`cat $OUTPUT/temp/EXTERNAL$i`
  SERVERS_INTERNAL[`expr $i - 1`]="$a"
  SERVERS_EXTERNAL[`expr $i - 1`]="$b"
done

rm -rf $OUTPUT/temp

echo ======== Instances ========
echo Internal IPs: ${SERVERS_INTERNAL[@]}
echo External IPs: ${SERVERS_EXTERNAL[@]}

# NOW START Ansible and wait for opened ssh service
