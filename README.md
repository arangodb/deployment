# deployment
<!---
### GCE (Google Compute Engine)
For deployment at google computing engine cloud you need the gcloud Tool Guide:
  - https://cloud.google.com/sdk/gcloud/

Create a three-instance cluster (GCE project id: cluster-0001):
```sh
$ ./create_gce_machines.sh -p cluster-0001 -n 3
```
-->
### DO (Digital Ocean)

Create a three-instance cluster:
```sh
$ chmod +x create_do_machines.sh
$ export TOKEN="your_token"
$ ./create_do_machines.sh -n 3
```
