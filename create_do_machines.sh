#!/bin/bash
set -e

REGION="sgp1"
SIZE="512mb"
NUMBER="3"
OUTPUT="digital_ocean"
TOKEN=""
IMAGE="coreos-stable"
SSHID=""

while getopts ":z:m:n:d:t:s:" opt; do
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
    t)
      TOKEN="$OPTARG"
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

#GET DROPLET
#curl -X GET -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" "https://api.digitalocean.com/v2/droplets/4566462"

PREFIX="arangodb-test-$$-"

echo "REGION: $REGION"
echo "SIZE: $SIZE"
echo "NUMBER OF MACHINES: $NUMBER"
echo "OUTPUT DIRECTORY: $OUTPUT"
echo "MACHINE PREFIX: $PREFIX"

if test -z "$TOKEN";  then
  echo "$0: you must supply a project with '-t'"
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

function createMachine () {
  echo "creating machine $PREFIX$1"

  curl --request POST "https://api.digitalocean.com/v2/droplets" \
       --header "Content-Type: application/json" \
       --header "Authorization: Bearer $TOKEN" \
       --data "{\"region\":\"$REGION\", \"image\":\"$IMAGE\", \"size\":\"$SIZE\", \"name\":\"$PREFIX$1\",
         \"ssh_keys\":[\"$SSHID\"], \"user_data\": \"\"}" \
       -s > $OUTPUT/curl.log
}

function getMachine () {

  touch $OUTPUT/ips

  while read line
  do

    name=$line
    ID=`echo "$name" | rev | cut -c 2- | rev`
    RESULT=`curl -X GET -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
                   "https://api.digitalocean.com/v2/droplets/$ID"`
    echo $RESULT | python -mjson.tool | grep "\"ip_address\"" | awk '{print $2}' | rev | cut -c 2- | rev >> $OUTPUT/ips
echo $RESULT
echo $ID
  done < $OUTPUT/hosts
}

for i in `seq $NUMBER`; do
  createMachine $i &
done

wait

#Wait until machines are ready.
while :
do
   FIRST=`cat $OUTPUT/hosts | head -n1 | rev | cut -c 2- | rev`
   RESULT2=`curl -X GET -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
                   "https://api.digitalocean.com/v2/droplets/$FIRST"`
   CHECK=`echo $RESULT2 | python -mjson.tool | grep "\"id\"" | head -n 1 | awk '{print $2}' | rev | cut -c 2- | rev`

  echo 1: $FIRST
  echo 2: $RESULT2
  echo 3: $CHECK

   sleep 5

   if [ "$CHECK" != "not_found" ];
   then
     echo ready: droplets now online. now installing arangodb.
     break;
   else
     echo waiting: droplets not ready yet...
   fi

done

getMachine $i &

wait

# NOW START Ansible and wait for opened ssh service
