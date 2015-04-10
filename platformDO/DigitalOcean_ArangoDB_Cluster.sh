# This starts multiple coreos instances using the digital ocean cloud platform
# and then starts an ArangoDB cluster on them.
#
# Use -r to permanently remove an existing cluster and all machine instances.
#
# Prerequisites:
# The following environment variables are used:
#   TOKEN  : digital ocean api-token (as environment variable)
#
# Optional prerequisites:
#   REGION : site of the server (e.g. -z nyc3)
#   SIZE   : size/machine-type of the instance (e.g. -m 512mb)
#   NUMBER : count of machines to create (e.g. -n 3)
#   OUTPUT : local output log folder (e.g. -d /my/directory)
#   SSHID  : id of your existing ssh keypair. if no id is set, a new
#            keypair will be generated and transfered to your created
#            instance (e.g. -s 123456)
#   PREFIX : prefix for your machine names (e.g. "export PREFIX="arangodb-test-$$-")

#set -e
set -u

REGION="ams3"
SIZE="4gb"
NUMBER="3"
OUTPUT="digital_ocean"
IMAGE="coreos-stable"
SSHID=""

function deleteMachine () {
  echo "deleting machine $PREFIX$1"
  id=${SERVERS_IDS_ARR[`expr $1 - 1`]}

  CURL=`curl --request DELETE "https://api.digitalocean.com/v2/droplets/$id" \
       --header "Content-Type: application/json" \
       --header "Authorization: Bearer $TOKEN" 2>/dev/null`
}

DigitalOceanDestroyMachines() {
    if [ ! -e "$OUTPUT" ] ;  then
      echo "$0: directory '$OUTPUT' not found"
      exit 1
    fi

    . $OUTPUT/clusterinfo.sh

    declare -a SERVERS_IDS_ARR=(${SERVERS_IDS[@]})

    NUMBER=${#SERVERS_IDS_ARR[@]}

    echo "NUMBER OF MACHINES: $NUMBER"
    echo "OUTPUT DIRECTORY: $OUTPUT"
    echo "MACHINE PREFIX: $PREFIX"

    if test -z "$TOKEN";  then
      echo "$0: you must supply a token as environment variable with 'export TOKEN='your_token''"
      exit 1
    fi

    export CLOUDSDK_CONFIG="$OUTPUT/digital_ocean"
    touch $OUTPUT/hosts
    touch $OUTPUT/curl.log
    CURL=""

    for i in `seq $NUMBER`; do
      deleteMachine $i &
    done

    wait

    exit 0
}

#COREOS PARAMS
declare -a SERVERS_EXTERNAL_DO
declare -a SERVERS_INTERNAL_DO
declare -a SERVERS_IDS_DO

SSH_USER="core"
SSH_KEY="arangodb_key"
SSH_CMD="ssh"
SSH_SUFFIX="-i $HOME/.ssh/arangodb_key -l $SSH_USER"

REMOVE=0

while getopts ":z:m:n:d:s:hr" opt; do
  case $opt in
    h)
      cat <<EOT
This starts multiple coreos instances using the digital ocean cloud platform

Use -r to permanently remove an existing cluster and all machine instances.

Prerequisites:
The following environment variables are used:
  TOKEN  : digital ocean api-token (as environment variable)

Optional prerequisites:
  REGION : site of the server (e.g. -z nyc3)
  SIZE   : size/machine-type of the instance (e.g. -m 512mb)
  NUMBER : count of machines to create (e.g. -n 3)
  OUTPUT : local output log folder (e.g. -d /my/directory)
  SSHID  : id of your existing ssh keypair. if no id is set, a new
           keypair will be generated and transfered to your created
           instance (e.g. -s 123456)
  PREFIX : prefix for your machine names (e.g. "export PREFIX="arangodb-test-$$-")
EOT
      exit 0
      ;;
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
    r)
      REMOVE=1
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

: ${TOKEN?"You must supply a token as environment variable with 'export TOKEN='your_token'"}

if test -e "$OUTPUT";  then
  if [ "$REMOVE" == "1" ] ; then
    DigitalOceanDestroyMachines
    exit 0
  fi

  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

if [ "$REMOVE" == "1" ] ; then
  echo "$0: did not find an existing directory '$OUTPUT'"
  exit 1
fi

echo "REGION: $REGION"
echo "SIZE: $SIZE"
echo "NUMBER OF MACHINES: $NUMBER"
echo "OUTPUT DIRECTORY: $OUTPUT"
echo "MACHINE PREFIX: $PREFIX"

wget -q --tries=10 --timeout=20 --spider http://google.com
if [[ $? -eq 0 ]]; then
        echo ""
else
        echo "No internet connection. Exiting."
        exit 1
fi

mkdir -p "$OUTPUT/temp"

if test -z "$SSHID";  then

  BOOL=0
  COUNTER=0

  if [ ! -f $HOME/.ssh/arangodb_key.pub ];

  then
    echo "No ArangoDB SSH-Key found. Generating a new one.!"
    ssh-keygen -t dsa -f $OUTPUT/$SSH_KEY -C "arangodb@arangodb.com"

    if [ $? -eq 0 ]; then
      echo OK
    else
      echo Failed to create SSH-Key. Exiting.
      exit 1
    fi

    cp $OUTPUT/$SSH_KEY* $HOME/.ssh/

    SSHPUB=`cat $HOME/.ssh/arangodb_key.pub`

    echo Deploying ssh keypair on digital ocean.
    CURL=`curl -s -S -D $OUTPUT/temp/header -X POST -H 'Content-Type: application/json' \
         -H "Authorization: Bearer $TOKEN" \
         -d "{\"name\":\"arangodb\",\"public_key\":\"$SSHPUB\"}" "https://api.digitalocean.com/v2/account/keys"`

    if [[ -s "$OUTPUT/temp/header" ]] ; then
      echo "Deployment of new ssh key successful."
      > $OUTPUT/temp/header
    else
      echo "Could not deploy keys. Exiting."
      exit 1
    fi ;

    SSHID=`echo $CURL | python -mjson.tool | grep "\"id\"" | awk '{print $2}' | rev | cut -c 2- | rev`

  else

    echo "ArangoDB SSH-Key found. Try to use $HOME/.ssh/arangodb_key.pub"
    LOCAL_KEY=`cat $HOME/.ssh/arangodb_key.pub | awk '{print $2}'`
    DOKEYS=`curl -D $OUTPUT/temp/header -s -S -X GET -H 'Content-Type: application/json' \
           -H "Authorization: Bearer $TOKEN" "https://api.digitalocean.com/v2/account/keys"`

    if [[ -s "$OUTPUT/temp/header" ]] ; then
      echo "Fetched deposited keys from digital ocean."
      > $OUTPUT/temp/header
    else
      echo "Could not fetch deposited keys from digital ocean. Exiting."
      exit 1
    fi ;

    echo $DOKEYS | python -mjson.tool | grep "\"public_key\"" | awk '{print $3}' > "$OUTPUT/temp/do_keys"
    echo $DOKEYS | python -mjson.tool | grep "\"id\"" | awk '{print $2}' | rev | cut -c 2- | rev > $OUTPUT/temp/do_keys_ids

    while read line
      do
        COUNTER=$[COUNTER + 1]

        if [ "$line" = "$LOCAL_KEY" ]
          then
              BOOL=1
            break;
        fi

    done < "$OUTPUT/temp/do_keys"

  fi

  if [ "$BOOL" -eq 1 ];

    then
      echo "SSH-Key is valid and already stored at digital ocean."
      SSHID=$(sed -n "${COUNTER}p" "$OUTPUT/temp/do_keys_ids")

    else
      echo "Your stored SSH-Key is not deployed."

        SSHPUB=`cat $HOME/.ssh/arangodb_key.pub`
        echo Deploying ssh keypair on digital ocean.
          CURL=`curl -s -S -D $OUTPUT/temp/header --request POST -H 'Content-Type: application/json' \
            -H "Authorization: Bearer $TOKEN" \
            -d "{\"name\":\"arangodb\",\"public_key\":\"$SSHPUB\"}" "https://api.digitalocean.com/v2/account/keys"`

        if [[ -s "$OUTPUT/temp/header" ]] ; then
          echo "Deployment of SSH-Key finished."
          > $OUTPUT/temp/header
        else
          echo "Could not deploy SSH-Key. Exiting."
          exit 1
        fi ;

        SSHID=`echo $CURL | python -mjson.tool | grep "\"id\"" | awk '{print $2}' | rev | cut -c 2- | rev`

  fi

fi

wait

#check if ssh agent is running
if [ -n "${SSH_AUTH_SOCK}" ]; then
    echo "SSH-Agent is running."

    #check if key already added to ssh agent
    if ssh-add -l | grep arangodb_key > /dev/null ; then
      echo SSH-Key already added to SSH-Agent;
    else
      ssh-add $HOME/.ssh/arangodb_key
    fi

  else
    echo "No SSH-Agent running. Skipping."

fi

export CLOUDSDK_CONFIG="$OUTPUT/digital_ocean"
touch $OUTPUT/hosts
touch $OUTPUT/curl.log
CURL=""

function createMachine () {
  echo "creating machine $PREFIX$1"

  CURL=`curl -s -S -D $OUTPUT/temp/header$1 --request POST "https://api.digitalocean.com/v2/droplets" \
       --header "Content-Type: application/json" \
       --header "Authorization: Bearer $TOKEN" \
       --data "{\"region\":\"$REGION\", \"image\":\"$IMAGE\", \"size\":\"$SIZE\", \"name\":\"$PREFIX$1\", \"ssh_keys\":[\"$SSHID\"], \"private_networking\":\"true\" }" 2>>$OUTPUT/curl.error`

  if [[ -s "$OUTPUT/temp/header$1" ]] ; then
    echo "Machine $PREFIX$1 created."
    > $OUTPUT/temp/header$1
  else
    echo "Could not create machine $PREFIX$1. Exiting."
    exit 1
  fi ;

  to_file=`echo $CURL | python -mjson.tool | grep "\"id\"" | head -n 1 | awk '{print $2}' | rev | cut -c 2- | rev`
  echo $to_file > "$OUTPUT/temp/INSTANCEID$1"
}

function getMachine () {
  id=`cat $OUTPUT/temp/INSTANCEID$i`

  #while loop until ip addresses are fetched successfully

  while :
  do

    if [[ -s "$OUTPUT/temp/INTERNAL$1" ]] ; then
      echo "Machine information from $PREFIX$1 fetched."
      break
    else
      RESULT2=`curl -s -S -D $OUTPUT/temp/header$1 -X GET -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
                              "https://api.digitalocean.com/v2/droplets/$id" 2>>$OUTPUT/curl.error`

      echo $RESULT2 >> $OUTPUT/curl.log

      if [[ -s "$OUTPUT/temp/header$1" ]] ; then
        echo "Getting status information from machine: $PREFIX$1."
        > $OUTPUT/temp/header$1
      else
        echo "Could not fetch machine information from $PREFIX$1. Exiting."
        exit 1
      fi ;

      a=`echo $RESULT2 | python -mjson.tool | grep "\"ip_address\"" | head -n 1 | awk '{print $2}' | cut -c 2- | rev | cut -c 3- | rev`
      b=`echo $RESULT2 | python -mjson.tool | grep "\"ip_address\"" | head -n 2 | tail -1 |awk '{print $2}' | cut -c 2- | rev | cut -c 3- | rev`

      if [ -n "$a" ]; then
        echo $a > "$OUTPUT/temp/INTERNAL$1"
      fi
      if [ -n "$b" ]; then
        echo $b > "$OUTPUT/temp/EXTERNAL$1"
      fi
    fi ;

    sleep 2

  done
}


for i in `seq $NUMBER`; do
  createMachine $i &
done

wait

for i in `seq $NUMBER`; do
  getMachine $i &
done

wait

while :
do

  FINISHED=0

  for i in `seq $NUMBER`; do

    if [ -s "$OUTPUT/temp/INTERNAL$i" ] ; then
      echo "Machine $PREFIX$i finished"
      FINISHED=1
    else
      echo "Machine $PREFIX$i not ready yet."
      FINISHED=0
      break
    fi

  done

  if [ $FINISHED == 1 ] ; then
    echo "All machines are set up"
    break
  fi

  sleep 1

done

wait


#Wait until machines are ready.
#while :
#do
#   firstid=`cat $OUTPUT/temp/INSTANCEID$i`
#   RESULT=`curl -s -S -X GET -H 'Content-Type: application/json' -H "Authorization: Bearer $TOKEN" \
#                   "https://api.digitalocean.com/v2/droplets/$firstid" 2>/dev/null`
#   CHECK=`echo $RESULT | python -mjson.tool | grep "\"id\"" | head -n 1 | awk '{print $2}' | rev | cut -c 2- | rev`
#
#   if [ "$CHECK" != "not_found" ];
#   then
#     echo ready: droplets now online.
#     break;
#   else
#     echo waiting: droplets not ready yet...
#   fi
#
#done
#wait

for i in `seq $NUMBER`; do
  a=`cat $OUTPUT/temp/INTERNAL$i`
  b=`cat $OUTPUT/temp/EXTERNAL$i`
  id=`cat $OUTPUT/temp/INSTANCEID$i`
  SERVERS_INTERNAL_DO[`expr $i - 1`]="$a"
  SERVERS_EXTERNAL_DO[`expr $i - 1`]="$b"
  SERVERS_IDS_DO[`expr $i - 1`]="$id"

done

rm -rf $OUTPUT/temp

echo Internal IPs: ${SERVERS_INTERNAL_DO[@]}
echo External IPs: ${SERVERS_EXTERNAL_DO[@]}
echo IDs         : ${SERVERS_IDS_DO[@]}

SERVERS_INTERNAL="${SERVERS_INTERNAL_DO[@]}"
SERVERS_EXTERNAL="${SERVERS_EXTERNAL_DO[@]}"
SERVERS_IDS="${SERVERS_IDS_DO[@]}"

# Write data to file:
echo > $OUTPUT/clusterinfo.sh "SERVERS_INTERNAL=\"$SERVERS_INTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_EXTERNAL=\"$SERVERS_EXTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_IDS=\"$SERVERS_IDS\""
echo >>$OUTPUT/clusterinfo.sh "SSH_USER=\"$SSH_USER\""
echo >>$OUTPUT/clusterinfo.sh "SSH_CMD=\"$SSH_CMD\""
echo >>$OUTPUT/clusterinfo.sh "SSH_SUFFIX=\"$SSH_SUFFIX\""
echo >>$OUTPUT/clusterinfo.sh "PREFIX=\"$PREFIX\""

# Export needed variables
export SERVERS_INTERNAL
export SERVERS_EXTERNAL
export SERVERS_IDS
export SSH_USER="core"
export SSH_CMD="ssh"
export SSH_SUFFIX="-i $HOME/.ssh/arangodb_key -l $SSH_USER"

# Wait for DO instances

sleep 10

startArangoDBClusterWithDocker
