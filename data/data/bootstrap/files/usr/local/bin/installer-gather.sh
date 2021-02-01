#!/usr/bin/env bash

if test "x${1}" = 'x--id'
then
	GATHER_ID="${2}"
	shift 2
fi

ARTIFACTS="/tmp/artifacts-${GATHER_ID}"
mkdir -p "${ARTIFACTS}"

# The existence of the file located in BOOTSTRAP_IN_PLACE_BOOTSTRAP_PHASE_ARCHIVE_PATH is used
# as indication that we're running inside a single-node bootstrap-in-place deployment post-pivot
# master node, rather than a typical bootstrap machine. In the former case, we extract some of
# the logs from said archive rather than actually collect them.
BOOTSTRAP_IN_PLACE_BOOTSTRAP_PHASE_LOG_BUNDLE_NAME="log-bundle-bootstrap-in-place-pre-reboot"
BOOTSTRAP_IN_PLACE_BOOTSTRAP_PHASE_ARCHIVE_PATH="/var/log/$BOOTSTRAP_IN_PLACE_BOOTSTRAP_PHASE_LOG_BUNDLE_NAME.tar.gz"
if [[ -f ${BOOTSTRAP_IN_PLACE_BOOTSTRAP_PHASE_ARCHIVE_PATH} ]]; then
    # single-node bootstrap-in-place deployment post-pivot master node log gathering

    exec &> >(tee "${ARTIFACTS}/bootstrap-in-place-post-pivot-gather.log")

    # Instead of gathering bootstrap logs, copy from the pre-preboot gather archive
    echo "Found log bundle from bootstrap phase, running in bootstrap-in-place post-pivot mode"
    tar -xzf ${BOOTSTRAP_IN_PLACE_BOOTSTRAP_PHASE_ARCHIVE_PATH}
    cp -r ${BOOTSTRAP_IN_PLACE_BOOTSTRAP_PHASE_LOG_BUNDLE_NAME}/* "${ARTIFACTS}/"

    # The KUBECONFIG for gathering control-plane resources is in a different location post-pivot
    GATHER_KUBECONFIG="/etc/kubernetes/bootstrap-secrets/kubeconfig"

    # Additional post-pivot journal to collect
    JOURNAL_SERVICES="bootstrap-in-place-post-reboot"

    # Instead of running installer-masters-gather.sh on remote masters, run it on ourselves
    MASTER_GATHER_ID="master-${GATHER_ID}"
    MASTER_ARTIFACTS="/tmp/artifacts-${MASTER_GATHER_ID}"
    mkdir -p "${ARTIFACTS}/control-plane/master"
    sudo /usr/local/bin/installer-masters-gather.sh --id "${MASTER_GATHER_ID}" </dev/null
    cp -r "$MASTER_ARTIFACTS"/* "${ARTIFACTS}/control-plane/master/"
else
    # Typical bootstrap log gathering

    exec &> >(tee "${ARTIFACTS}/gather.log")

    GATHER_KUBECONFIG="/opt/openshift/auth/kubeconfig"
    JOURNAL_SERVICES="release-image crio-configure bootkube kubelet crio approve-csr ironic master-bmh-update"

    echo "Gathering bootstrap systemd summary ..."
    LANG=POSIX systemctl list-units --state=failed >& "${ARTIFACTS}/failed-units.txt"
    echo "Gathering bootstrap failed systemd unit status ..."
    mkdir -p "${ARTIFACTS}/unit-status"
    sed -n 's/^\* \([^ ]*\) .*/\1/p' < "${ARTIFACTS}/failed-units.txt" | while read -r UNIT
    do
        systemctl status --full "${UNIT}" >& "${ARTIFACTS}/unit-status/${UNIT}.txt"
        journalctl -u "${UNIT}" > "${ARTIFACTS}/unit-status/${UNIT}.log"
    done

    echo "Gathering bootstrap containers ..."
    mkdir -p "${ARTIFACTS}/bootstrap/containers"
    sudo crictl ps --all --quiet | while read -r container
    do
        container_name="$(sudo crictl ps -a --id "${container}" -v | grep -oP "Name: \\K(.*)")"
        sudo crictl logs "${container}" >& "${ARTIFACTS}/bootstrap/containers/${container_name}-${container}.log"
        sudo crictl inspect "${container}" >& "${ARTIFACTS}/bootstrap/containers/${container_name}-${container}.inspect"
    done
    sudo cp -r /var/log/bootstrap-control-plane/ "${ARTIFACTS}/bootstrap/containers"
    mkdir -p "${ARTIFACTS}/bootstrap/pods"
    sudo podman ps --all --quiet | while read -r container
    do
        sudo podman logs "${container}" >& "${ARTIFACTS}/bootstrap/pods/${container}.log"
        sudo podman inspect "${container}" >& "${ARTIFACTS}/bootstrap/pods/${container}.inspect"
    done

    echo "Gathering rendered assets..."
    mkdir -p "${ARTIFACTS}/rendered-assets"
    sudo cp -r /var/opt/openshift/ "${ARTIFACTS}/rendered-assets"
    sudo chown -R "${USER}":"${USER}" "${ARTIFACTS}/rendered-assets"
    sudo find "${ARTIFACTS}/rendered-assets" -type d -print0 | xargs -0 sudo chmod u+x
    # remove sensitive information
    # TODO leave tls.crt inside of secret yaml files
    find "${ARTIFACTS}/rendered-assets" -name "*secret*" -print0 | xargs -0 rm -rf
    find "${ARTIFACTS}/rendered-assets" -name "*kubeconfig*" -print0 | xargs -0 rm
    find "${ARTIFACTS}/rendered-assets" -name "*.key" -print0 | xargs -0 rm
    find "${ARTIFACTS}/rendered-assets" -name ".kube" -print0 | xargs -0 rm -rf

    echo "Gather remote logs"
    export MASTERS=()
    if [ "$#" -ne 0 ]; then
        MASTERS=( "$@" )
    elif test -s "${ARTIFACTS}/resources/masters.list"; then
        mapfile -t MASTERS < "${ARTIFACTS}/resources/masters.list"
    else
        echo "No masters found!"
    fi

    for master in "${MASTERS[@]}"
    do
        echo "Collecting info from ${master}"
        scp -o PreferredAuthentications=publickey -o StrictHostKeyChecking=false -o UserKnownHostsFile=/dev/null -q /usr/local/bin/installer-masters-gather.sh "core@[${master}]:"
        mkdir -p "${ARTIFACTS}/control-plane/${master}"
        ssh -o PreferredAuthentications=publickey -o StrictHostKeyChecking=false -o UserKnownHostsFile=/dev/null "core@${master}" -C "sudo ./installer-masters-gather.sh --id '${GATHER_ID}'" </dev/null
        scp -o PreferredAuthentications=publickey -o StrictHostKeyChecking=false -o UserKnownHostsFile=/dev/null -r -q "core@[${master}]:/tmp/artifacts-${GATHER_ID}/*" "${ARTIFACTS}/control-plane/${master}/"
    done
fi

echo "Gathering bootstrap journals ..."
mkdir -p "${ARTIFACTS}/bootstrap/journals"
for service in ${JOURNAL_SERVICES}
do
    journalctl --boot --no-pager --output=short --unit="${service}" > "${ARTIFACTS}/bootstrap/journals/${service}.log"
done

mkdir -p "${ARTIFACTS}/control-plane" "${ARTIFACTS}/resources"

# Collect cluster data
function queue() {
    local TARGET="${ARTIFACTS}/${1}"
    shift
    # shellcheck disable=SC2155
    local LIVE="$(jobs | wc -l)"
    while [[ "${LIVE}" -ge 45 ]]; do
        sleep 1
        LIVE="$(jobs | wc -l)"
    done
    # echo "${@}"
    if [[ -n "${FILTER}" ]]; then
        # shellcheck disable=SC2024
        sudo KUBECONFIG="${GATHER_KUBECONFIG}" "${@}" | "${FILTER}" >"${TARGET}" &
    else
        # shellcheck disable=SC2024
        sudo KUBECONFIG="${GATHER_KUBECONFIG}" "${@}" >"${TARGET}" &
    fi
}

echo "Gathering cluster resources ..."
queue resources/nodes.list oc --request-timeout=5s get nodes -o jsonpath --template '{range .items[*]}{.metadata.name}{"\n"}{end}'
queue resources/masters.list oc --request-timeout=5s get nodes -o jsonpath -l 'node-role.kubernetes.io/master' --template '{range .items[*]}{.metadata.name}{"\n"}{end}'
# ShellCheck doesn't realize that $ns is for the Go template, not something we're trying to expand in the shell
# shellcheck disable=2016
queue resources/containers oc --request-timeout=5s get pods --all-namespaces --template '{{ range .items }}{{ $name := .metadata.name }}{{ $ns := .metadata.namespace }}{{ range .spec.containers }}-n {{ $ns }} {{ $name }} -c {{ .name }}{{ "\n" }}{{ end }}{{ range .spec.initContainers }}-n {{ $ns }} {{ $name }} -c {{ .name }}{{ "\n" }}{{ end }}{{ end }}'
queue resources/api-pods oc --request-timeout=5s get pods -l apiserver=true --all-namespaces --template '{{ range .items }}-n {{ .metadata.namespace }} {{ .metadata.name }}{{ "\n" }}{{ end }}'

queue resources/apiservices.json oc --request-timeout=5s get apiservices -o json
queue resources/clusteroperators.json oc --request-timeout=5s get clusteroperators -o json
queue resources/clusterversion.json oc --request-timeout=5s get clusterversion -o json
queue resources/configmaps.json oc --request-timeout=5s get configmaps --all-namespaces -o json
queue resources/csr.json oc --request-timeout=5s get csr -o json
queue resources/endpoints.json oc --request-timeout=5s get endpoints --all-namespaces -o json
queue resources/events.json oc --request-timeout=5s get events --all-namespaces -o json
queue resources/kubeapiserver.json oc --request-timeout=5s get kubeapiserver -o json
queue resources/kubecontrollermanager.json oc --request-timeout=5s get kubecontrollermanager -o json
queue resources/machineconfigpools.json oc --request-timeout=5s get machineconfigpools -o json
queue resources/machineconfigs.json oc --request-timeout=5s get machineconfigs -o json
queue resources/namespaces.json oc --request-timeout=5s get namespaces -o json
queue resources/nodes.json oc --request-timeout=5s get nodes -o json
queue resources/openshiftapiserver.json oc --request-timeout=5s get openshiftapiserver -o json
queue resources/pods.json oc --request-timeout=5s get pods --all-namespaces -o json
queue resources/rolebindings.json oc --request-timeout=5s get rolebindings --all-namespaces -o json
queue resources/roles.json oc --request-timeout=5s get roles --all-namespaces -o json
# this just lists names and number of keys
queue resources/secrets-names.txt oc --request-timeout=5s get secrets --all-namespaces
# this adds annotations, but strips out the SA tokens and dockercfg secrets which are noisy and may contain secrets in the annotations
queue resources/secrets-names-with-annotations.txt oc --request-timeout=5s get secrets --all-namespaces -o=custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,TYPE:.type,ANNOTATIONS:.metadata.annotations | grep -v -- '-token-' | grep -v -- '-dockercfg-'
queue resources/services.json oc --request-timeout=5s get services --all-namespaces -o json

FILTER=gzip queue resources/openapi.json.gz oc --request-timeout=5s get --raw /openapi/v2

echo "Waiting for logs ..."
wait

TAR_FILE="${TAR_FILE:-${HOME}/log-bundle-${GATHER_ID}.tar.gz}"
tar cz -C "${ARTIFACTS}" --transform "s?^\\.?log-bundle-${GATHER_ID}?" . > "${TAR_FILE}"
echo "Log bundle written to ${TAR_FILE}"
