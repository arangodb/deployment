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
declare -a SERVERS_EXTERNAL_DO
declare -a SERVERS_INTERNAL_DO
SSH_USER="core"
SSH_KEY="arangodb_key"
SSH_CMD="ssh"
SSH_SUFFIX="-i $HOME/.ssh/arangodb_key -l $SSH_USER"

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
mkdir "$OUTPUT/temp"

if test -z "$SSHID";  then

  if [ ! -f $HOME/.ssh/arangodb_key.pub ];

  then
    echo "No ArangoDB ssh key found. Generating a new one.!"
    ssh-keygen -t dsa -f $OUTPUT/$SSH_KEY -C "arangodb@arangodb.com"

    cp $OUTPUT/$SSH_KEY* $HOME/.ssh/

    SSHPUB=`cat $HOME/.ssh/arangodb_key.pub`

    echo Deploying ssh keypair on digital ocean.
    SSHID=`curl -X POST -H 'Content-Type: application/json' \
         -H "Authorization: Bearer $TOKEN" \
         -d "{\"name\":\"arangodb\",\"public_key\":\"$SSHPUB\"}" "https://api.digitalocean.com/v2/account/keys" \
         | python -mjson.tool | grep "\"id\"" | awk '{print $2}' | rev | cut -c 2- | rev`

  else

  BOOL=0

    echo "ArangoDB SSH-Key found. Using $HOME/.ssh/arangodb_key.pub"
    LOCAL_KEY=`cat $HOME/.ssh/arangodb_key.pub | awk '{print $2}'`
    DOKEYS=`curl -X GET -H 'Content-Type: application/json' \
           -H "Authorization: Bearer $TOKEN" "https://api.digitalocean.com/v2/account/keys"`

    # TODO WRITE KEYS AND KEY IDS TO TEMP FILES
    echo $(DOKEYS) | python -mjson.tool | grep "\"public_key\"" | awk '{print $3}' > "$OUTPUT/temp/do_keys"
    #echo $DOKEYS | python -mjson.tool | grep "\"id\"" | awk '{print $2}' | rev | cut -c 2- | rev > $OUTPUT/temp/do_keys_ids

    exit 1

    while read line
      do

        if [ "$line" = "$LOCAL_KEY" ]
          then
              BOOL=1
            break;
        fi

    if [ $BOOL -eq 1]

      then
      #TODO: LOOK FOR VALID ID AND STORE IT DO KEY ID VARIABLE
        echo "Key is valid."

      else
        echo "Key is not deployed. Please remove $HOME/.ssh/arangodb_key.pub and re-run the script."
        exit 1
    fi

    done < $OUTPUT/temp/do_keys

    exit 1

  fi
fi

wait

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
     echo ready: droplets now online.
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
  SERVERS_INTERNAL_DO[`expr $i - 1`]="$a"
  SERVERS_EXTERNAL_DO[`expr $i - 1`]="$b"
done

rm -rf $OUTPUT/temp

echo Internal IPs: ${SERVERS_INTERNAL_DO[@]}
echo External IPs: ${SERVERS_EXTERNAL_DO[@]}

SERVERS_INTERNAL="${SERVERS_INTERNAL_DO[@]}"
SERVERS_EXTERNAL="${SERVERS_EXTERNAL_DO[@]}"

# Export needed variables
export SERVERS_INTERNAL
export SERVERS_EXTERNAL
export SSH_USER="core"
export SSH_CMD="ssh"
export SSH_SUFFIX="-i $HOME/.ssh/arangodb_key -l $SSH_USER"

# Wait for do instances
sleep 10

./startDockerCluster.sh
