#!/usr/bin/env bash

if [ -z "${CLUSTER_NAME}" ]; then
	echo CLUSTER_NAME environment variable is not set
	exit 1
fi
if [ -z "${AWS_ACCOUNT_ID}" ]; then
	echo AWS_ACCOUNT_ID environment variable is not set
	exit 1
fi

eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" --name k8s-node-latency --namespace k8s-node-latency \
  --role-name "${CLUSTER_NAME}-k8s-node-latency" \
  --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/K8sNodeLatencyPolicy-${CLUSTER_NAME}" \
  --role-only \
  --approve
