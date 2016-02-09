# This starts multiple coreos instances using amazon web services and then
# starts an ArangoDB cluster on them.
#
# Use -r to permanently remove an existing cluster and all machine instances.
#
# Optional prerequisites:
# The following environment variables are used:
#
#   SIZE    : size/machine-type of the instance (e.g. -m n1-standard-2)
#   NUMBER  : count of machines to create (e.g. -n 3)
#   OUTPUT  : local output log folder (e.g. -d /my/directory)

if [ platformAWS/AmazonWebServices_ArangoDB_Cluster.sh -nt ./AmazonWebServices_ArangoDB_Cluster.sh ] || [ Docker/ArangoDBClusterWithDocker.sh -nt ./AmazonWebServices_ArangoDB_Cluster.sh ] ; then
  echo 'You almost certainly have forgotten to say "make" to assemble this'
  echo 'script from its parts in subdirectories. Stopping.'
  exit 1
fi

trap "kill 0" SIGINT

#CoreOS AWS Image List
#https://coreos.com/docs/running-coreos/cloud-providers/ec2/

MACHINE_TYPE="t1.medium"
NUMBER="3"
OUTPUT="aws"
SSH_KEY_PATH=""

function deleteMachine () {
  echo "deleting machine $PREFIX$1"
  id=${SERVERS_IDS_ARR[`expr $1 - 1`]}

  aws ec2 terminate-instances --instance-ids "$id"

  if [ $? -eq 0 ]; then
    echo "OK: Deleted instance $id"
  else
    echo "ERROR: instance $id could not be deleted."
  fi
}

AmazonWebServicesDestroyMachines() {

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

    for i in `seq $NUMBER`; do
      deleteMachine $i &
    done

    wait

    echo "Removing old Security Group: ${PREFIX}security"
    sleep 45
    aws ec2 delete-security-group --group-name "${PREFIX}security"

    echo "Removing old SSH-Keys: ${PREFIX}aws-ssh-key"
    aws ec2 delete-key-pair --key-name "${PREFIX}aws-ssh-key"
    rm -f "$HOME/.ssh/${PREFIX}aws-ssh-key"*

    wait

    read -p "Delete directory: '$OUTPUT' ? [y/n]: " -n 1 -r
      echo
    if [[ $REPLY =~ ^[Yy]$ ]]
      then
        rm -r "$OUTPUT"
        echo "Directory deleted. Finished."
      else
        echo "For a new cluster instance, please remove the directory or specifiy another output directory with -d '/my/directory'"
    fi

    exit 0
}

REMOVE=0

while getopts ":m:n:d:s:hr" opt; do
  case $opt in
    h)
       cat <<EOT
This starts multiple coreos instances using amazon web services and then
starts an ArangoDB cluster on them.

Use -r to permanently remove an existing cluster and all machine instances.

Optional prerequisites:
The following environment variables are used:

  SIZE    : size/machine-type of the instance (e.g. -m n1-standard-2)
  NUMBER  : count of machines to create (e.g. -n 3)
  OUTPUT  : local output log folder (e.g. -d /my/directory)
EOT
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
    r)
      REMOVE=1
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
echo "OUTPUT DIRECTORY: $OUTPUT"
echo "ZONE: $ZONE"
echo "PROJECT: $PROJECT"

DEFAULT_KEY_PATH="$HOME/.ssh/${PREFIX}aws-ssh-key"

#check if project is already set
zone=`cat $HOME/.aws/config | grep region |awk {'print $3'}`

if test -z "$zone";  then
  echo "AWS zone is not configured. Please run: aws configure"
  exit 1
else
  ZONE=$zone
fi

#We have to keep all ami's up to date
# Current Version: CoreOS 607.0.0
# URL: https://coreos.com/docs/running-coreos/cloud-providers/ec2/

if [ "$zone" == "eu-central-1" ]; then
  IMAGE="ami-0e300d13"
fi

if [ "$zone" == "ap-northeast-1" ]; then
  IMAGE="ami-af28dcaf"
fi

if [ "$zone" == "sa-east-1" ]; then
  IMAGE="ami-2354ec3e"
fi

if [ "$zone" == "ap-southeast-2" ]; then
  IMAGE="ami-b9b5c583"
fi

if [ "$zone" == "ap-southeast-1" ]; then
  IMAGE="mi-f80b3aaa"
fi

if [ "$zone" == "us-east-1" ]; then
  IMAGE="ami-323b195a"
fi

if [ "$zone" == "us-west-2" ]; then
  IMAGE="ami-0789a437"
fi

if [ "$zone" == "us-west-1" ]; then
  IMAGE="ami-8dd533c9"
fi

if [ "$zone" == "eu-west-1" ]; then
  IMAGE="ami-55950a22"
fi


if test -e "$OUTPUT";  then
  if [ "$REMOVE" == "1" ] ; then
    AmazonWebServicesDestroyMachines
    exit 0
  fi

  echo "$0: refusing to use existing directory '$OUTPUT'"
  exit 1
fi

if [ "$REMOVE" == "1" ] ; then
  echo "$0: did not find an existing directory '$OUTPUT'"
  exit 1
fi

echo "MACHINE_TYPE: $MACHINE_TYPE"
echo "NUMBER OF MACHINES: $NUMBER"
echo "MACHINE PREFIX: $PREFIX"

mkdir -p "$OUTPUT/temp"

if [[ -s "$HOME/.ssh/${PREFIX}aws-ssh-key" ]] ; then
  echo "AWS SSH-Key existing."
else
  echo "No AWS SSH-Key existing. Creating a new SSH-Key."

  ssh-keygen -t rsa -C "${PREFIX}aws-ssh-key" -f "$OUTPUT"/${PREFIX}aws-ssh-key

  if [ $? -eq 0 ]; then
    echo OK
  else
    echo Failed to create SSH-Key. Exiting.
    exit 1
  fi

  cp "$OUTPUT/${PREFIX}aws-ssh-key"* "$HOME/.ssh/"
  chmod 400 "$HOME"/.ssh/${PREFIX}aws-ssh-key
  aws ec2 import-key-pair --key-name "${PREFIX}aws-ssh-key" --public-key-material file://$HOME/.ssh/${PREFIX}aws-ssh-key.pub

fi ;

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

#echo "Creating VPC"
#a=`aws ec2 create-vpc --cidr-block 10.0.0.0/16`
#
#echo $a
#echo ========
#echo
#vpcid=`echo a | python -mjson.tool | grep VpcId | awk {'print $9'} | cut -c 2- | rev | cut -c 3- | rev`

#echo $vpcid 
#exit 1 
#echo $vpcid > $OUTPUT/vpcid

#echo "Creating Subnet"
#aws ec2 create-subnet --vpc-id "$vpcid" --cidr-block 10.0.1.0/24 --availability-zone "$ZONE"
#subnetid=`echo a | python -mjson.tool | grep SubnetId | awk {'print $2'} | cut -c 2- | rev | cut -c 3- | rev`
#echo $subnetid > $OUTPUT/subnetid

#exit 1


echo "Creating Security Group"
#secureid=`aws ec2 describe-security-groups --output json --group-names ${PREFIX}security |python -mjson.tool|grep GroupId| awk {'print $2'}| cut -c 2- | rev | cut -c 3- | rev`
aws ec2 create-security-group \
    --group-name "${PREFIX}security" \
    --description "Open SSH and needed ArangoDB Ports"

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 22

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 8529

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 8629

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 7001

wait
aws ec2 authorize-security-group-ingress \
    --group-name "${PREFIX}security" \
    --cidr 0.0.0.0/0 \
    --protocol tcp --port 4001

    #--source-group "$secureid" \
wait

function getMachine () {
  currentid=`cat $OUTPUT/temp/IDS$1`
  public=`aws ec2 describe-instances --output json --instance-ids $currentid | grep PublicIpAddress | awk '{print $2}' | cut -c 2- | rev | cut -c 3- | rev`

  state=0
  while [ "$state" == 0 ]; do
    if test -z "$public";  then
     echo "Machine $PREFIX$1 not ready yet."
     sleep 3
    else
     echo "Machine $PREFIX$1 ready."
     state=1
    fi
  done

  echo $public > "$OUTPUT/temp/EXTERNAL$1"
}

function createMachine () {
  echo "creating machine $PREFIX$1"

  INSTANCE=`aws ec2 run-instances --output json --image-id "$IMAGE" --count 1 --instance-type t2.medium \
  --key-name "${PREFIX}aws-ssh-key" --associate-public-ip-address --subnet-id "$subnetid"`

  id=`echo $INSTANCE | python -mjson.tool | grep InstanceId | awk '{print $2}' | cut -c 2- | rev | cut -c 3- | rev`
  priv=`echo $INSTANCE | python -mjson.tool | grep PrivateIpAddress | awk '{print $2}' | head -n 1 | cut -c 2- | rev | cut -c 3- | rev`

  echo $priv > "$OUTPUT/temp/INTERNAL$1"
  echo $id > "$OUTPUT/temp/IDS$1"
}

function setMachineName () {
  echo "Setting up machine names."
  id=`cat "$OUTPUT/temp/IDS$i"`
  aws ec2 create-tags --resources $id --tags Key=Name,Value=$PREFIX$1
}

function setMachineSecurity () {
  echo "Adding security groups."
  id=`cat "$OUTPUT/temp/IDS$i"`
  secureid=`aws ec2 describe-security-groups --output json --group-names ${PREFIX}security |python -mjson.tool|grep GroupId| awk {'print $2'}| cut -c 2- | rev | cut -c 3- | rev`
  aws ec2 modify-instance-attribute --instance-id "$id" --groups "$secureid"
}

#CoreOS PARAMS
declare -a SERVERS_EXTERNAL_AWS
declare -a SERVERS_INTERNAL_AWS
declare -a SERVERS_IDS_AWS

SSH_USER="core"
SSH_CMD="ssh"

for i in `seq $NUMBER`; do
  createMachine $i &
done

wait

sleep 5

for i in `seq $NUMBER`; do
  getMachine $i &
done

wait

for i in `seq $NUMBER`; do
  setMachineName $i &
done

wait

for i in `seq $NUMBER`; do
  setMachineSecurity $i &
done

wait

while :
do

  FINISHED=0

  for i in `seq $NUMBER`; do

    if [ -s "$OUTPUT/temp/INTERNAL$i" ] ; then
      SERVERS_INTERNAL_AWS[`expr $i - 1`]=`cat "$OUTPUT/temp/INTERNAL$i"`
      SERVERS_EXTERNAL_AWS[`expr $i - 1`]=`cat "$OUTPUT/temp/EXTERNAL$i"`
      SERVERS_IDS_AWS[`expr $i - 1`]=`cat "$OUTPUT/temp/IDS$i"`
      FINISHED=1
    else
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

echo Internal IPs: ${SERVERS_INTERNAL_AWS[@]}
echo External IPs: ${SERVERS_EXTERNAL_AWS[@]}
echo IDs         : ${SERVERS_IDS_AWS[@]}

echo Remove host key entries in ~/.ssh/known_hosts...
for ip in ${SERVERS_EXTERNAL_AWS[@]} ; do
  ssh-keygen -f ~/.ssh/known_hosts -R $ip
done

SERVERS_INTERNAL="${SERVERS_INTERNAL_AWS[@]}"
SERVERS_EXTERNAL="${SERVERS_EXTERNAL_AWS[@]}"
SERVERS_IDS="${SERVERS_IDS_AWS[@]}"

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

sleep 5

startArangoDBClusterWithDocker
