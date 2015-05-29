# ArangoDB fast-deployment tools

Collection of bash scripts which deploy an ArangoDB Cluster on several cloud services platforms. 

![ArangoDB-Deployment](https://raw.githubusercontent.com/hkernbach/images/master/arangodb/deployment/aranogdb_deploy_img.png)

##Get Started

Here you'll find all information you need to easily start a complete arangodb cluster. Currently we're offering fast deploy on following cloud platforms: 
 * Amazon Web Services
 * Digital Ocean
 * Google Compute Engine
 * Microsoft Azure
 
There will be coming more supported platforms in the future. Feel free to contact us if you have a special desire for a particular cloud service platform. In order to use the scripts, please follow the instructions listed below.

#### DO (Digital Ocean)

#####Create a cluster:
```sh
$ wget https://raw.githubusercontent.com/ArangoDB/deployment/publish/DigitalOcean_ArangoDB_Cluster.sh
$ chmod +x DigitalOcean_ArangoDB_Cluster.sh
$ export TOKEN="your_digital-ocean_token"
$ ./DigitalOcean_ArangoDB_Cluster.sh 
```

#####Remove existing cluster:
```sh
./DigitalOcean_ArangoDB_Cluster.sh -r
```

#### GCE (Google Compute Engine)

#####Prerequisites:

To use the google bash script, you need the Google gcloud tool installed and configured. You can skip this part, if that already happened.

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

#####Create a cluster:
```sh
$ wget https://raw.githubusercontent.com/ArangoDB/deployment/publish/GoogleComputeEngine_ArangoDB_Cluster.sh
$ chmod 755 GoogleComputeEngine_ArangoDB_Cluster.sh
```
