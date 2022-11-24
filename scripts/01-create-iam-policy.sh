#!/usr/bin/env bash

if [ -z "${CLUSTER_NAME}" ]; then
	echo CLUSTER_NAME environment variable is not set
	exit 1
fi

aws cloudformation deploy \
  --stack-name "K8sNodeLatency-${CLUSTER_NAME}" \
  --template-file cloudformation.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"
