#!/bin/bash
set -e

ZONE="europe-west1-b"
MACHINE_TYPE="f1-micro"
NUMBER="3"
OUTPUT="gce"
PROJECT=""

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

ssh-keygen -t dsa -f gce/ssh-key -C "arangodb@arangodb.com" -N ""

function createMachine () {
  echo "creating machine $PREFIX$1"
  INSTANCE=`gcloud compute instances create --image coreos --zone "$ZONE" --machine-type "$MACHINE_TYPE" "$PREFIX$1" | grep "^$PREFIX"`

  a=`echo $INSTANCE | awk '{print $4}'`
  b=`echo $INSTANCE | awk '{print $5}'`

  SERVERS_INTERNAL[$1-1]="$a"
  SERVERS_EXTERNAL[$1-1]="$b"

}

#CoreOS PARAMS
declare -a SERVERS_EXTERNAL
declare -a SERVERS_INTERNAL
SSH_USER="arangodb"
SSH_CMD="gcloud compute ssh"
SSH_PARAM="/bin/true"
SSH_SUFFIX="--ssh-key-file gce/ssh-key --project "$PROJECT" --zone "$ZONE" --command "$SSH_PARAM" "arangodb@${PREFIX}1""

#function createUser () {
  #gcloud compute ssh --ssh-key-file gce/ssh-key --zone "$ZONE" --command "sudo useradd -u 1337 -U -m -G adm,sudo,dip,video,plugdev arangodb" "$PREFIX$1"
#}

for i in `seq $NUMBER`; do
  createMachine $i &
  sleep 1
done

wait

# Have to wait until google deployed keys on all instances.
sleep 20
gcloud compute ssh --ssh-key-file gce/ssh-key --project "$PROJECT" --zone "$ZONE" --command "/bin/true" "arangodb@${PREFIX}1"

