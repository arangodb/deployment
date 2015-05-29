# ArangoDB fast-deployment tools

Collection of bash scripts which deploy an ArangoDB Cluster on several cloud services platforms. 

![ArangoDB-Deployment](https://raw.githubusercontent.com/hkernbach/images/master/arangodb/deployment/aranogdb_deploy_img.png)

## Get Started

Here you'll find all information you need to easily start a complete arangodb cluster. Currently we're offering fast deploy on following cloud platforms: 
 * [Digital Ocean](#digital-ocean)
 * [Google Compute Engine](#google-compute-engine)
 * [Amazon Web Services](#amazon-web-services)
 * [Microsoft Azure](#microsoft-azure)
 
There will be coming more supported platforms in the future. Feel free to contact us if you have a special desire for a particular cloud service platform. In order to use the scripts, please follow the instructions listed below.

### Digital Ocean

##### Create a cluster:
```sh
$ wget https://raw.githubusercontent.com/ArangoDB/deployment/publish/DigitalOcean_ArangoDB_Cluster.sh
$ chmod +x DigitalOcean_ArangoDB_Cluster.sh
$ export TOKEN="your_digital-ocean_token"
$ ./DigitalOcean_ArangoDB_Cluster.sh 
```

##### Remove existing cluster:
```sh
./DigitalOcean_ArangoDB_Cluster.sh -r
```

### Google Compute Engine 

To use the google bash script, you need the Google gcloud tool installed and configured. You can skip this part, if that already happened.

##### Prerequisites:

Install Google gcloud tool:
```sh
$ curl https://sdk.cloud.google.com | bash
```
and restart your shell or terminal. Then use gcloud tool for authentication:
```sh
$ gcloud auth login
```
... set your proect-id:
```sh
$ gcloud config set project "your-project-id"
```
... and set your zone: 
```sh
$ gcloud config set zone "your-desired-zone" 
```
Please use this command to list all available zones:
```sh
$ gcloud compute zones list
```

##### Create a cluster:
```sh
$ wget https://raw.githubusercontent.com/ArangoDB/deployment/publish/GoogleComputeEngine_ArangoDB_Cluster.sh
$ chmod 755 GoogleComputeEngine_ArangoDB_Cluster.sh
$ ./GoogleComputeEngine_ArangoDB_Cluster.sh
```

##### Remove existing cluster:
```sh
$ ./GoogleComputeEngine_ArangoDB_Cluster.sh -r
```

### Amazon Web Services

The script needs the awscli installed and configured. You can skip this part if your awscli tool is already installed and fully configured. Otherwise please follow these steps:

##### Prerequisites:

Install awscli (python and pip required):
```sh
 $ sudo pip install awscli
```
... and configure awscli:
```sh
 $ aws configure
```

You will be asked for: 
 * AWS Access Key ID
 * AWS Secret Access Key
 * Default region name
 * Default output format (optional)

##### Create a cluster:
```sh
$ wget wget https://raw.githubusercontent.com/ArangoDB/deployment/publish/AmazonWebServices_ArangoDB_Cluster.sh
$ chmod 755 AmazonWebServices_ArangoDB_Cluster.sh
$ ./AmazonWebServices_ArangoDB_Cluster.sh
```

##### Remove existing cluster:
```sh
$ ./AmazonWebServices_ArangoDB_Cluster.sh -r
```

### Microsoft Azure

The script needs the azure-cli installed and configured. You can skip this part if azure-cli is already installed and fully configured. Otherwise please follow these steps:

##### Prerequisites:

Install npm (skip if npm already is installed):
```sh
$ sudo apt-get install nodejs-legacy 
$ sudo apt-get install npm
```
Install azure-cli (skip if azure-cli already is installed) :
```sh
$ sudo npm install -g azure-cli
```
Then authorize with azure-cli (skip if azure-cli already is installed AND configured).
There are two ways for authentication:

a) Login via publish settings file
```sh
$ azure account download
```
Then launch the browser with the given url (example: http://go.microsoft.com/fwlink/?LinkId=12345). After a successful login, a file with your credentials will be downloaded. In the next step, import the file to your azure-cli.
```sh
$ azure account import <path-to-downloaded-file> (example: /tmp/BizSpark\ Plus-5-26-2015-credentials.publishsettings)
```

or

b) Login via organizational account (if available)
```sh
$ azure login
```

##### Create a cluster:
```sh
$ wget https://raw.githubusercontent.com/ArangoDB/deployment/publish/Azure_ArangoDB_Cluster.sh
$ chmod 755 Azure_ArangoDB_Cluster.sh
$ ./Azure_ArangoDB_Cluster.sh
```

##### Remove existing cluster:
```sh
$ ./Azure_ArangoDB_Cluster.sh -r
```

## Build From Source
Optionally, you can build all deployment scripts from its source on Github. 
```sh
$ git clone git@github.com:arangodb/deployment.git
$ cd deployment
$ make
```

##Some switches to configure a few things

Use the -h parameter to get a help page.
Optional prerequisites The following environment variables are used:

 * SIZE : change the size/machine-type of the instance (e.g. -m t1.medium)
 * NUMBER : change the count of machines to create (e.g. -n 3, the default is 3)
 * OUTPUT : change the local output log folder (e.g. -d /my/directory)

Please remember that some variables may slightly differ like e.g. the size parameter. Each cloud platform service has their own naming for them. Some scripts may offer more modification (use -h to display them).

## Some background information for the curious
This script will use the azure-cli authentication for Azure to deploy a number of VM instances running CoreOS. If you do not already have one, it will first create a SSH keypair for you and deploy it to Azure and your ssh-agent. Once the machines are running, the script uses Docker images to start up all components of an ArangoDB cluster and link them to each other. In the end, it will print out access information.

No installation of ArangoDB is needed neither on the VM instances nor on your machine. All deployment issues are taken care of by Docker. You can simply sit back and enjoy.

The whole process will take a few minutes and will print out some status reports.
