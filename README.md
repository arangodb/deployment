![ArangoDB-Deployment](https://raw.githubusercontent.com/hkernbach/images/master/arangodb/deployment/aranogdb_deploy_img.png)

# ArangoDB fast-deployment tools
Collection of bash scripts which deploy an ArangoDB Cluster on several cloud services platforms. 

Get Started
-----------

#### DO (Digital Ocean)

Create a cluster:
```sh
$ wget https://raw.githubusercontent.com/ArangoDB/deployment/publish/DigitalOcean_ArangoDB_Cluster.sh
$ chmod +x DigitalOcean_ArangoDB_Cluster.sh
$ export TOKEN="your_digital-ocean_token"
$ ./DigitalOcean_ArangoDB_Cluster.sh 
```

Remove existing cluster:
```sh
./DigitalOcean_ArangoDB_Cluster.sh -r
```

#### GCE (Google Compute Engine)
For deployment at google computing engine cloud you need the gcloud Tool Guide:
  - https://cloud.google.com/sdk/gcloud/

Create a three-instance cluster (example gce project id: cluster-0001):
```sh
$ wget https://raw.githubusercontent.com/ArangoDB/deployment/publish/GoogleComputeEngine_ArangoDB_Cluster.sh
$ chmod 755 GoogleComputeEngine_ArangoDB_Cluster.sh
```
