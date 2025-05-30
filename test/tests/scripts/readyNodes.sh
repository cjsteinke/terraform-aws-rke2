#!/bin/bash



if [ -n "$WAIT" ]; then echo "you will have $WAIT seconds to investigate errors before destruction"; fi

echo "attempting to contact cluster..."

echo "first let's check the endpoint $API..."
curl -vvvL "$API"

echo "now lets check using kubectl..."
if kubectl get nodes; then
  echo "cluster responding..."
else
  echo "cluster not responding..."
  if [ -n "$WAIT" ]; then
    echo "you have $WAIT seconds to investigate errors before destruction...";
    sleep "$WAIT"
  fi
  exit 1
fi

JSONPATH="'{range .items[*]}
  {.metadata.name}{\"\\t\"} \
  {.status.nodeInfo.kubeletVersion}{\"\\t\"} \
  {.status.nodeInfo.osImage}{\"\\t\"} \
  {.status.nodeInfo.architecture}{\"\\t\"} \
  {.status.conditions[?(@.status==\"True\")].type}{\"\\n\"} \
{end}'"

notReady() {
  # Get the list of nodes and their statuses  
  NODES="$(kubectl get nodes -o jsonpath="$JSONPATH" || true)"
  # Example output:
  # master-node   Ready
  # worker-node   Ready MemoryPressure
  # worker-node2  EtcVoter Ready
  # worker-node3  
  # shellcheck disable=SC2060,SC2140
  NOT_READY="$(echo "$NODES" | grep -v "Ready" | tr -d ["\t","\n"," ","'"] || true)"
  if [ -n "$NOT_READY" ]; then
    # Some nodes are not ready
    return 0
  else
    # All nodes are ready
    return 1
  fi
}

TIMEOUT=10 # 10 minutes
TIMEOUT_MINUTES=$((TIMEOUT * 60))
INTERVAL=10 # 10 seconds
MAX=$((TIMEOUT_MINUTES / INTERVAL))
INDEX=0

while notReady; do
  if [[ $INDEX -lt $MAX ]]; then
    echo "Waiting for nodes to be ready..."
    INDEX=$((INDEX + 1))
    sleep $INTERVAL;
  else
    echo "Timeout reached. Nodes are not ready..."
    kubectl get nodes || true
    kubectl get all -A

    if [ -n "$WAIT" ]; then echo "you have $WAIT seconds to investigate errors before destruction..."; fi
    sleep "$WAIT"
    exit 1
  fi
done

kubectl get nodes || true
kubectl get all -A || true
exit 0
