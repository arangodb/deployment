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

while getopts ":z:m:n:d:p:" opt; do
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

mkdir "$OUTPUT"

export CLOUDSDK_CONFIG="$OUTPUT/gce"

gcloud config set account arangodb
gcloud config set project "$PROJECT"
gcloud auth login

if test -z "$SSH_KEY_PATH";
then
  echo "No SSH-Key-Path given. Creating a new SSH-Key."

  ssh-keygen -t dsa -f gce/ssh-key -C "arangodb@arangodb.com"

  if [ $? -eq 0 ]; then
    echo Created SSH-Key.
  else
    echo Failed to create SSH-Key. Exiting.
    exit 1
  fi

else
  #Check if SSH-Files are available and valid
  ssh-keygen -l -f $SSH_KEY_PATH

  if [ $? -eq 0 ]; then
    echo SSH-Key is valid.
  else
    echo Failed to validate SSH-Key. Exiting.
    exit 1
  fi

fi

exit 1

#check if ssh agent is running
if [ -n "${SSH_AUTH_SOCK}" ]; then
    echo "SSH-Agent is running."

    #check if key already added to ssh agent
    if ssh-add -l | grep arangodb_key > /dev/null ; then
      echo SSH-Key already added to SSH-Agent;
    else
      ssh-add -K $HOME/.ssh/arangodb_key
    fi

  else
    echo "No SSH-Agent running. Skipping."

fi

function createMachine () {
  echo "creating machine $PREFIX$1"
  INSTANCE=`gcloud compute instances create --image coreos --zone "$ZONE" --machine-type "$MACHINE_TYPE" "$PREFIX$1" | grep "^$PREFIX"`

  a=`echo $INSTANCE | awk '{print $4}'`
  b=`echo $INSTANCE | awk '{print $5}'`

  SERVERS_INTERNAL_GCE[$1-1]="$a"
  SERVERS_EXTERNAL_GCE[$1-1]="$b"

}

#CoreOS PARAMS
declare -a SERVERS_EXTERNAL_GCE
declare -a SERVERS_INTERNAL_GCE
SSH_USER="arangodb"
SSH_CMD="gcloud compute ssh"
SSH_PARAM="/bin/true"
SSH_SUFFIX="--ssh-key-file gce/ssh-key --project "$PROJECT" --zone "$ZONE" --command "$SSH_PARAM" "arangodb@${PREFIX}1""

for i in `seq $NUMBER`; do
  createMachine $i &
  sleep 1
done

wait

# Have to wait until google deployed keys on all instances.
sleep 20
gcloud compute ssh --ssh-key-file gce/ssh-key --project "$PROJECT" --zone "$ZONE" --command "/bin/true" "arangodb@${PREFIX}1"

