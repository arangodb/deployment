#!/bin/bash

# This starts multiple coreos instances using microsoft azure
#
# Optional prerequisites:
#   ZONE  : size of the server (e.g. -z "US West")
#   SIZE    : size/machine-type of the instance (e.g. -m Medium)
#   NUMBER  : count of machines to create (e.g. -n 3)
#   OUTPUT  : local output log folder (e.g. -d /my/directory)
#   SSH     : path to your already on azure deployed ssh key (e.g. -s /my/directory/mykey)

trap "kill 0" SIGINT

ZONE="West US"
MACHINE_TYPE="Medium"
NUMBER="3"
OUTPUT="azure"
IMAGE="2b171e93f07c4903bcad35bda10acf22__CoreOS-Stable-607.0.0"
SSH_KEY_PATH=""
DEFAULT_KEY_PATH="$OUTPUT/arangodb_azure_key"

DEPLOY_KEY=0

while getopts ":z:m:n:d:s:h:" opt; do
  case $opt in
    h)
    cat <<EOT
This starts multiple coreos instances using microsoft azure

Optional prerequisites:
  ZONE  : size of the server (e.g. -z "US West")
  SIZE    : size/machine-type of the instance (e.g. -m Medium)
  NUMBER  : count of machines to create (e.g. -n 3)
  OUTPUT  : local output log folder (e.g. -d /my/directory)
  SSH     : path to your already on azure deployed ssh key (e.g. -s /my/directory/mykey)

EOT
    exit 0
    ;;
    z)
      ZONE="$OPTARG"
      ;;
    m)
      MACHINE_TYPE="$OPTARG"
      ;;
    n)
      NUMBER="$OPTARG"
      ;;
    d)
      OUTPUT="$OPTARG"
      ;;
    s)
      SSH_KEY_PATH="$OPTARG"
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

echo "ZONE: $ZONE"
echo "MACHINE_TYPE: $MACHINE_TYPE"
echo "NUMBER OF MACHINES: $NUMBER"
echo "OUTPUT DIRECTORY: $OUTPUT"
echo "PROJECT: $PROJECT"
echo "MACHINE PREFIX: $PREFIX"

if test -e "$OUTPUT";  then
  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

mkdir -p "$OUTPUT/temp"

export CLOUDSDK_CONFIG="$OUTPUT/azure"

#gcloud config set account arangodb
#gcloud config set project "$PROJECT"
#gcloud auth login

if test -z "$SSH_KEY_PATH";
then

  if [[ -s "$HOME/.ssh/arangodb_azure_key" ]] ; then
    echo "ArangoDB Azure SSH-Key found."
    DEFAULT_KEY_PATH="$HOME/.ssh/arangodb_azure_key"
  else
    echo "No SSH-Key-Path given. Creating a new SSH-Key."
    ssh-keygen -t dsa -f "$DEFAULT_KEY_PATH" -C "arangodb@arangodb.com"

#    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout "$DEFAULT_KEY_PATH" -out "$DEFAULT_KEY_PATH.pem"
    openssl req -x509 -key "$DEFAULT_KEY_PATH" -nodes -days 365 -newkey rsa:2048 -out "${DEFAULT_KEY_PATH}.pem"

    if [ $? -eq 0 ]; then
      echo Created SSH-Key.
    else
      echo Failed to create SSH-Key. Exiting.
      exit 1
    fi
    cp $DEFAULT_KEY_PATH* $HOME/.ssh/
    DEFAULT_KEY_PATH="$HOME/.ssh/arangodb_azure_key"
    chmod 600 $DEFAULT_KEY_PATH
  fi ;

else
  #Check if SSH-Files are available and valid
  echo "Trying to use $SSH_KEY_PATH."
  DEFAULT_KEY_PATH="$SSH_KEY_PATH"
  ssh-keygen -l -f "$DEFAULT_KEY_PATH"

  if [ $? -eq 0 ]; then
    echo SSH-Key is valid.
  else
    echo Failed to validate SSH-Key. Exiting.
    exit 1
  fi
fi


#check if ssh agent is running
if [ -n "${SSH_AUTH_SOCK}" ]; then
    echo "SSH-Agent is running."

    #check if key already added to ssh agent
    if ssh-add -l | grep $DEFAULT_KEY_PATH > /dev/null ; then
      echo SSH-Key already added to SSH-Agent;
    else
      ssh-add "$DEFAULT_KEY_PATH"
    fi

  else
    echo "No SSH-Agent running. Skipping."

fi

function getMachine () {

  state=""

  while [ "$state" != "ReadyRole" ]; do
    instance=`azure vm show "$PREFIX$1"`
    state=`echo "$instance" | grep InstanceStatus | awk '{print $3}' | cut -c 2- | rev | cut -c 2- | rev`
  done

  internalip=`echo "$instance" | grep IPAddress | head -n 1 |awk '{print $3}' | cut -c 2- | rev | cut -c 2- | rev`
  externalip=`echo "$instance" | grep virtualIPAddress | awk '{print $6}' | cut -c 2- | rev | cut -c 2- | rev`

  if [ -n "$internalip" ]; then
    echo $internalip > "$OUTPUT/temp/INTERNAL$1"
  fi
  if [ -n "$externalip" ]; then
    echo $externalip > "$OUTPUT/temp/EXTERNAL$1"
  fi
}

function createMachine () {
  echo "creating machine $PREFIX$1"
  azure vm create --vm-size "$MACHINE_TYPE" --userName "core" --ssh 22 --ssh-cert "${DEFAULT_KEY_PATH}.pem" \
  --no-ssh-password "$PREFIX$1" "$IMAGE"

  if [ $? -eq 0 ]; then
    echo
  else
    echo Failed to create machine $PREFIX$1. Retrying.
      createMachine $i &
  fi
}

#CoreOS PARAMS
declare -a SERVERS_EXTERNAL_AZURE
declare -a SERVERS_INTERNAL_AZURE
declare -a SERVERS_IDS_AZURE

SSH_USER="arangodb"
SSH_CMD="gcloud compute ssh"
SSH_PARAM="/bin/true"

for i in `seq $NUMBER`; do
  echo "Creating services for virtual machines."
  # not parallel because azure cannot spawn multiple services at the same time
  azure service create "$PREFIX$i" --location "$ZONE"
done

for i in `seq $NUMBER`; do
  sleep 2
  createMachine $i &
done

wait

# get machines information
for i in `seq $NUMBER`; do
  sleep 2
  getMachine $i &
done

#wait

while :
do

  FINISHED=0

  for i in `seq $NUMBER`; do

    if [ -s "$OUTPUT/temp/INTERNAL$i" ] ; then
      SERVERS_INTERNAL_AZURE[`expr $i - 1`]=`cat "$OUTPUT/temp/INTERNAL$i"`
      SERVERS_EXTERNAL_AZURE[`expr $i - 1`]=`cat "$OUTPUT/temp/EXTERNAL$i"`
      SERVERS_IDS_AZURE[`expr $i - 1`]=$PREFIX$i
      FINISHED=1
    else
      echo "Machine $PREFIX$i not ready yet."
      sleep 5
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

rm -rf $OUTPUT/temp

echo Internal IPs: ${SERVERS_INTERNAL_AZURE[@]}
echo External IPs: ${SERVERS_EXTERNAL_AZURE[@]}
echo IDs         : ${SERVERS_IDS_AZURE[@]}

SERVERS_INTERNAL="${SERVERS_INTERNAL_AZURE[@]}"
SERVERS_EXTERNAL="${SERVERS_EXTERNAL_AZURE[@]}"
SERVERS_IDS="${SERVERS_IDS_AZURE[@]}"

# Write data to file:
echo > $OUTPUT/clusterinfo.sh "SERVERS_INTERNAL=\"$SERVERS_INTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_EXTERNAL=\"$SERVERS_EXTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_IDS=\"$SERVERS_IDS\""
echo >>$OUTPUT/clusterinfo.sh "SSH_USER=\"$SSH_USER\""
echo >>$OUTPUT/clusterinfo.sh "SSH_CMD=\"$SSH_CMD\""
echo >>$OUTPUT/clusterinfo.sh "SSH_SUFFIX=\"$SSH_SUFFIX\""
echo >>$OUTPUT/clusterinfo.sh "PREFIX=\"$PREFIX\""
echo >>$OUTPUT/clusterinfo.sh "ZONE=\"$ZONE\""

# Export needed variables
export SERVERS_INTERNAL
export SERVERS_EXTERNAL
export SERVERS_IDS
export SSH_USER="core"
export SSH_CMD="ssh"
export SSH_SUFFIX="-i $DEFAULT_KEY_PATH -l $SSH_USER"
export ZONE

./startDockerCluster.sh
