#!/usr/bin/env bash
set -eu
exec > >(tee /var/log/user-data-metrics.log|logger -t user-data -s 2>/dev/console) 2>&1
EVENTS=()
NAMESPACE="LaunchCanary"
EXPERIMENT="none"
if [[ $# -eq 1 ]]; then
    EXPERIMENT=$1
fi

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
ID_DOC=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN"  http://169.254.169.254/latest/dynamic/instance-identity/document)
AWS_REGION=$(echo ${ID_DOC} | jq -r '.region')
INSTANCE_TYPE=$(echo ${ID_DOC} | jq -r '.instanceType')
INSTANCE_ID=$(echo ${ID_DOC} | jq -r '.instanceId')
PENDING_TIME=$(echo ${ID_DOC} | jq -r '.pendingTime')
PENDING_SECONDS=$(date -d "${PENDING_TIME}" '+%s')
## Don't have a great way to get this, so assume the request latency is 1 second from the pending time
INSTANCE_REQUEST_SECONDS=$(( ${PENDING_SECONDS} - 1 ))

function emit_metric() {
    local name=$1
    local val=$2
    aws cloudwatch put-metric-data --region "${AWS_REGION}" --metric-name "${name}" --namespace "${NAMESPACE}" --unit Seconds --value "${val}" --dimensions InstanceType=${INSTANCE_TYPE},Experiment=${EXPERIMENT}
}

function event() {
    local unit=$1
    local prop=$2
    local description=$3
    local _time=$(systemctl show ${unit} --property=${prop} | cut -d '=' -f2- | cut -d ' ' -f2-3)
    local _seconds=$(date -d "${_time}" '+%s')
    local _t=$(( ${_seconds} - ${INSTANCE_REQUEST_SECONDS} ))
    echo "${_t} ${description} $(date -d "${_time}" '+%T')"
}

function messages_event() {
    local message=$1
    local description=$2
    local _time=$(cat /var/log/messages | grep "${message}" | tr -s " " | cut -d' ' -f1-3)
    local _seconds=$(date -d "${_time}" '+%s')
    local _t=$(( ${_seconds} - ${INSTANCE_REQUEST_SECONDS} ))
    echo "${_t} ${description} $(date -d "${_time}" '+%T')"
}

while true; do
    sleep 1
    EVENTS=()
    EVENTS+=("0 Instance Request")
    PENDING_T=$(( ${PENDING_SECONDS} - ${INSTANCE_REQUEST_SECONDS} ))
    EVENTS+=("${PENDING_T} Instance Created $(date -d "${PENDING_TIME}" '+%T')")
    VM_INIT_TIME=$(uptime -s)
    VM_INIT_SECONDS=$(date -d "${VM_INIT_TIME}" '+%s')
    VM_INIT_T=$(( ${VM_INIT_SECONDS} - ${INSTANCE_REQUEST_SECONDS} ))
    EVENTS+=("${VM_INIT_T} VM Initialized $(date -d "${VM_INIT_TIME}" '+%T')")

    EVENTS+=("$(event "network" "ActiveEnterTimestamp" "Network Target Start")")
    NETWORK_START_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "network-online.target" "ActiveEnterTimestamp" "Network Target Ready")")
    NETWORK_READY_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "cloud-init" "ExecMainStartTimestamp" "Cloud-Init Initial Starts")")
    CLOUD_INIT_INITIAL_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "cloud-init" "ExecMainExitTimestamp" "Cloud-Init Initial z-Exits")")
    CLOUD_INIT_INITIAL_EXIT_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "cloud-config" "ExecMainStartTimestamp" "Cloud-Init Config Starts")")
    CLOUD_INIT_CONFIG_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "cloud-config" "ExecMainExitTimestamp" "Cloud-Init Config z-Exits")")
    CLOUD_INIT_CONFIG_EXIT_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "cloud-final" "ExecMainStartTimestamp" "Cloud-Init Final Starts")")
    CLOUD_INIT_FINAL_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "cloud-final" "ExecMainExitTimestamp" "Cloud-Init Final (user-data) z-Exits")")
    CLOUD_INIT_FINAL_EXIT_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "containerd" "ExecMainStartTimestamp" "ContainerD Starts")")
    CONTAINERD_START_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(event "kubelet" "ExecMainStartTimestamp" "Kubelet Starts")")
    KUBELET_START_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(messages_event "Successfully registered node" "Kubelet Node Registration")")
    KUBELET_REGISTRATION_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    EVENTS+=("$(messages_event 'CreateContainer within sandbox .*Name:kube-proxy.* returns container id' "kube-proxy Started")")
    KUBE_PROXY_STARTED_T=$(echo "${EVENTS[-1]}" | cut -d' ' -f1)

    POD_START_TIME=$(cat /var/log/messages |grep 'default/.* Type:ContainerStarted' | head -n1 | tr -s " " | cut -d' ' -f1-3)
    POD_START_TIME_SECONDS=$(date -d "${POD_START_TIME}" '+%s')
    POD_START_TIME_T=$(( ${POD_START_TIME_SECONDS} - ${INSTANCE_REQUEST_SECONDS} ))
    EVENTS+=("${POD_START_TIME_T} Pod Starts $(date -d "${POD_START_TIME}" '+%T')")
    # emit_metric "PodStartTime" "${POD_START_TIME_T}"

    NODE_READY_TIME=""
    if [[ -f /etc/cni/net.d/10-aws.conflist ]]; then
        NODE_READY_TIME=$(journalctl -u kubelet | grep -m1 'event="NodeReady"' | cut -d' ' -f1-3)
        if [[ ! -z ${NODE_READY_TIME} ]]; then
            VPC_CNI_INIT_CONTAINER_START_TIME=$(cat /var/log/pods/kube-system_aws-node-*/aws-vpc-cni-init/*.log | head -n1 | cut -d' ' -f1)
            VPC_CNI_INIT_CONTAINER_START_SECONDS=$(date -d "${VPC_CNI_INIT_CONTAINER_START_TIME}" '+%s')
            VPC_CNI_INIT_CONTAINER_START_T=$(( ${VPC_CNI_INIT_CONTAINER_START_SECONDS} - ${INSTANCE_REQUEST_SECONDS} ))
            EVENTS+=("${VPC_CNI_INIT_CONTAINER_START_T} VPC CNI Init Container Starts $(date -d "${VPC_CNI_INIT_CONTAINER_START_TIME}" '+%T')")

            AWS_NODE_START_TIME=$(cat /var/log/pods/kube-system_aws-node-*/aws-node/*.log | head -n1 | cut -d' ' -f1)
            AWS_NODE_START_SECONDS=$(date -d "${AWS_NODE_START_TIME}" '+%s')
            AWS_NODE_START_T=$(( ${AWS_NODE_START_SECONDS} - ${INSTANCE_REQUEST_SECONDS} ))
            EVENTS+=("${AWS_NODE_START_T} AWS Node Container Starts $(date -d "${AWS_NODE_START_TIME}" '+%T')")

            VPC_CNI_PLUGIN_INIT_TIME=$(cat /var/log/pods/kube-system_aws-node-*/aws-node/*.log | grep 'Successfully copied CNI plugin binary and config file.' | cut -d' ' -f1)
            VPC_CNI_PLUGIN_INIT_SECONDS=$(date -d "${VPC_CNI_PLUGIN_INIT_TIME}" '+%s')
            VPC_CNI_PLUGIN_INIT_T=$(( ${VPC_CNI_PLUGIN_INIT_SECONDS} - ${INSTANCE_REQUEST_SECONDS} ))
            EVENTS+=("${VPC_CNI_PLUGIN_INIT_T} VPC CNI Plugin Initialized $(date -d "${VPC_CNI_PLUGIN_INIT_TIME}" '+%T')")

            emit_metric "VPCCNIInitContainerStartTime" "${VPC_CNI_INIT_CONTAINER_START_T}"
            emit_metric "AWSNodeStartTime" "${AWS_NODE_START_T}"
            emit_metric "VPCCNIPluginInit" "${VPC_CNI_PLUGIN_INIT_T}"
        fi
    elif [[ -f /etc/cni/net.d/10-cni.conf ]]; then
        NODE_READY_TIME=$(journalctl -u kubelet | grep -m1 'Watching apiserver' | cut -d' ' -f1-3)
    fi

    if [[ -z ${NODE_READY_TIME} ]]; then
        echo "Node not ready yet!"
        continue
    fi
    NODE_READY_SECONDS=$(date -d "${NODE_READY_TIME}" '+%s')
    NODE_READY_T=$(( ${NODE_READY_SECONDS} - ${INSTANCE_REQUEST_SECONDS} ))
    EVENTS+=("${NODE_READY_T} Node Ready $(date -d "${NODE_READY_TIME}" '+%T')")
    echo "K8s Node is ready"
    emit_metric "Pending" "${PENDING_T}"
    emit_metric "VMInit" "${VM_INIT_T}"
    emit_metric "NetworkStart" "${NETWORK_START_T}"
    emit_metric "NetworkReady" "${NETWORK_READY_T}"
    emit_metric "CloudInitInitialStart" "${CLOUD_INIT_INITIAL_T}"
    emit_metric "CloudInitInitialFinish" "${CLOUD_INIT_INITIAL_EXIT_T}"
    emit_metric "CloudInitConfigStart" "${CLOUD_INIT_CONFIG_T}"
    emit_metric "CloudInitConfigFinish" "${CLOUD_INIT_CONFIG_EXIT_T}"
    emit_metric "CloudInitFinalStart" "${CLOUD_INIT_FINAL_T}"
    emit_metric "CloudInitFinalFinish" "${CLOUD_INIT_FINAL_EXIT_T}"
    emit_metric "ContainerdStart" "${CONTAINERD_START_T}"
    emit_metric "KubeletStart" "${KUBELET_START_T}"
    emit_metric "KubeletRegistered" "${KUBELET_REGISTRATION_T}"
    emit_metric "KubeProxyStarted" "${KUBE_PROXY_STARTED_T}"
    emit_metric "NodeReadyLatency" "${NODE_READY_T}"

    out_dir="${AWS_REGION}_${INSTANCE_TYPE}_${INSTANCE_ID}_${NODE_READY_T}s"
    mkdir -p "/tmp/${out_dir}"

    IFS=$'\n' SORTED_EVENTS=($(sort -n <<<"${EVENTS[*]}"))
    unset IFS

    echo "## ${INSTANCE_TYPE} - ${INSTANCE_ID}" > /tmp/${out_dir}/latency
    echo "| Event | Time (seconds) | " >> /tmp/${out_dir}/latency
    echo "| ----- | -------------- | " >> /tmp/${out_dir}/latency

    for event in "${SORTED_EVENTS[@]}"; do
        echo -n "| " >> /tmp/${out_dir}/latency
        echo -n "$(echo "${event}" | cut -d' ' -f2-)" >> /tmp/${out_dir}/latency
        echo -n " | " >> /tmp/${out_dir}/latency
        echo -n "$(echo "${event}" | cut -d' ' -f1)" >> /tmp/${out_dir}/latency
        echo " | " >> /tmp/${out_dir}/latency
    done
    exit 0
done
