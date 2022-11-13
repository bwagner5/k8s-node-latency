# K8s Node Latency (KNL)

The K8s Node Latency tool analyzes logs on a K8s node and outputs a timing chart and cloudwatch metrics. This tool is intended to analyze the components that contribute to the node launch latency so that they can be optimized to bring nodes online faster.


## Usage:

```
> measure.sh MyExperiment
```

The experiment name will be added as a cloudwatch metric dimension so that you are able to run multiple experiments and separate dimensions.

A directory wil be created with the name dervied from the region, instance-type, instance-id, and total latency: `/tmp/us-west-2-m5.large-i-0123456789-30s`
There will be a latency file in the directory which will output a table in markdown formate with each contributing process latency in node ready path.

The script will also emit cloudwatch metrics for each individual process latency.


## How to use:

You can embed this script into your user-data script and start it in the background or build the script directly into the machine image you are testing:

```
METRICS_SCRIPT=$(cat measure.sh  | base64)
```

```
mkdir -p /usr/local/bin/
echo "${METRICS_SCRIPT}" | base64 -d > /usr/local/bin/measure.sh
chmod +x /usr/local/bin/measure.sh
nohup /usr/local/bin/measure.sh <Experiment Name> &
```
