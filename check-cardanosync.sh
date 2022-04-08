#!/bin/sh
# In percent with three decimals but an integer - anything less will show as not synced
MIN_SYNC_DISTANCE=99999
SYNC=$(curl -s -m2 -N -X GET -H "accept: application/json" "https://${HAPROXY_SERVER_NAME}/health")
echo "${SYNC}" | grep -q "networkSynchronization"
if [ $? -ne 0 ]; then
  return 1
fi
SYNC=$(echo "${SYNC}" | jq .networkSynchronization)
SYNC=$(echo "${SYNC}*100000/1" | bc)
if [ "${SYNC}" -ge "${MIN_SYNC_DISTANCE}" ]; then
  return 0
else
  return 1
fi

