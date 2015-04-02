#!/bin/bash

# This starts multiple coreos instances using google compute engine
#
# Prerequisites:
# The following environment variables are used:
#   PROJECT : project id of your designated project (e.g. -p "project_id");
#
# Optional prerequisites:
#   ZONE  : size of the server (e.g. -z europe-west1-b)
#   SIZE    : size/machine-type of the instance (e.g. -m n1-standard-2)
#   NUMBER  : count of machines to create (e.g. -n 3)
#   OUTPUT  : local output log folder (e.g. -d /my/directory)
#   SSH     : path to your already on gce deployed ssh key (e.g. -s /my/directory/mykey)

ZONE="europe-west1-b"
MACHINE_TYPE="f1-micro"
NUMBER="3"
OUTPUT="gce"
PROJECT=""
SSH_KEY_PATH=""
DEFAULT_KEY_PATH="$OUTPUT/arangodb_gce_key"

DEPLOY_KEY=0

while getopts ":z:m:n:d:p:s:" opt; do
  case $opt in
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
    p)
      PROJECT="$OPTARG"
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

if test -z "$PROJECT";  then
  echo "$0: you must supply a project with '-p'"
  exit 1
fi

if test -e "$OUTPUT";  then
  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

mkdir -p "$OUTPUT/temp"

export CLOUDSDK_CONFIG="$OUTPUT/gce"

gcloud config set account arangodb
gcloud config set project "$PROJECT"
gcloud auth login

if test -z "$SSH_KEY_PATH";
then

  if [[ -s "$HOME/.ssh/arangodb_gce_key" ]] ; then
    echo "ArangoDB GCE SSH-Key existing."
    DEFAULT_KEY_PATH="$HOME/.ssh/arangodb_gce_key"
  else
    echo "No SSH-Key-Path given. Creating a new SSH-Key."
    ssh-keygen -t dsa -f "$DEFAULT_KEY_PATH" -C "arangodb@arangodb.com"

    if [ $? -eq 0 ]; then
      echo Created SSH-Key.
    else
      echo Failed to create SSH-Key. Exiting.
      exit 1
    fi
    DEPLOY_KEY=1
    cp $DEFAULT_KEY_PATH* $HOME/.ssh/
    DEFAULT_KEY_PATH="$HOME/.ssh/arangodb_gce_key"
  fi ;

else
  #Check if SSH-Files are available and valid
  echo "Trying to use $SSH_KEY_PATH."
  DEFAULT_KEY_PATH="$SSH_KEY_PATH"
  ssh-keygen -l -f "$DEFAULT_KEY_PATH"

  read -p "Deploy your SSH-Key? Only needed if not already deployed: y/n " -n 1 -r
    echo
  if [[ $REPLY =~ ^[Yy]$ ]]
  then
    DEPLOY_KEY=1
  fi

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

function createMachine () {
  echo "creating machine $PREFIX$1"
  INSTANCE=`gcloud compute instances create --image coreos --zone "$ZONE" --machine-type "$MACHINE_TYPE" "$PREFIX$1" | grep "^$PREFIX"`

  a=`echo $INSTANCE | awk '{print $4}'`
  b=`echo $INSTANCE | awk '{print $5}'`

  echo $a > "$OUTPUT/temp/INTERNAL$1"
  echo $b > "$OUTPUT/temp/EXTERNAL$1"
}

#CoreOS PARAMS
declare -a SERVERS_EXTERNAL_GCE
declare -a SERVERS_INTERNAL_GCE
declare -a SERVERS_IDS_GCE

SSH_USER="arangodb"
SSH_CMD="gcloud compute ssh"
SSH_PARAM="/bin/true"

for i in `seq $NUMBER`; do
  createMachine $i &
  sleep 1
done

wait

while :
do

  FINISHED=0

  for i in `seq $NUMBER`; do

    if [ -s "$OUTPUT/temp/INTERNAL$i" ] ; then
      echo "Machine $PREFIX$i finished"
      SERVERS_INTERNAL_GCE[`expr $i - 1`]=`cat "$OUTPUT/temp/INTERNAL$i"`
      SERVERS_EXTERNAL_GCE[`expr $i - 1`]=`cat "$OUTPUT/temp/EXTERNAL$i"`
      SERVERS_IDS_GCE[`expr $i - 1`]=$PREFIX$i
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

rm -rf $OUTPUT/temp

echo Internal IPs: ${SERVERS_INTERNAL_GCE[@]}
echo External IPs: ${SERVERS_EXTERNAL_GCE[@]}
echo IDs         : ${SERVERS_IDS_GCE[@]}

SERVERS_INTERNAL="${SERVERS_INTERNAL_GCE[@]}"
SERVERS_EXTERNAL="${SERVERS_EXTERNAL_GCE[@]}"
SERVERS_IDS="${SERVERS_IDS_GCE[@]}"

# Write data to file:
echo > $OUTPUT/clusterinfo.sh "SERVERS_INTERNAL=\"$SERVERS_INTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_EXTERNAL=\"$SERVERS_EXTERNAL\""
echo >>$OUTPUT/clusterinfo.sh "SERVERS_IDS=\"$SERVERS_IDS\""
echo >>$OUTPUT/clusterinfo.sh "SSH_USER=\"$SSH_USER\""
echo >>$OUTPUT/clusterinfo.sh "SSH_CMD=\"$SSH_CMD\""
echo >>$OUTPUT/clusterinfo.sh "SSH_SUFFIX=\"$SSH_SUFFIX\""
echo >>$OUTPUT/clusterinfo.sh "PREFIX=\"$PREFIX\""
echo >>$OUTPUT/clusterinfo.sh "ZONE=\"$ZONE\""
echo >>$OUTPUT/clusterinfo.sh "PROJECT=\"$PROJECT\""

# Export needed variables
export SERVERS_INTERNAL
export SERVERS_EXTERNAL
export SERVERS_IDS
export SSH_USER="arangodb"
export SSH_CMD="ssh"
export SSH_SUFFIX="-i $DEFAULT_KEY_PATH -l $SSH_USER"
export ZONE
export PROJECT

# Have to wait until google deployed keys on all instances.
echo "Now waiting for Google SSH-Key distribution."
sleep 45

if [ $DEPLOY_KEY == 1 ]; then
  gcloud compute ssh --ssh-key-file "$DEFAULT_KEY_PATH" --project "$PROJECT" --zone "$ZONE" --command "/bin/true" "arangodb@${PREFIX}1"
else
  echo "No need for key deployment."
fi

sleep 15

./startDockerCluster.sh
