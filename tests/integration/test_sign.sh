#!/bin/bash -x
set -euo pipefail
IFS=$'\n\t'

# Test scripts run with PWD=tests/..

# The test harness exports some variables into the environment during
# testing: PYTHONPATH (python module import path
#          WORK_DIR   (a directory that is safe to modify)
#          DOCKER     (the docker executable location)
#          ATOMIC     (an invocation of 'atomic' which measures code coverage)
#          SECRET     (a generated sha256 hash inserted into test containers)

# In addition, the test harness creates some images for use in testing.
#   See tests/test-images/

setup () {
    set +e # disable fail on error
    docker pull docker.io/library/registry:2
    docker run -d -p 5001:5000 --name atomic-test-registry docker.io/library/registry:2
    sleep 5
    GNUPGHOME=${WORK_DIR} gpg2 --import ${PWD}/tests/unit/fixtures/key2.asc
    docker tag atomic-test-secret localhost:5001/atomic-test-sign:latest
    ${ATOMIC} trust add localhost:5001 --pubkeys ${PWD}/tests/unit/fixtures/key2.pub --sigstore file:///var/lib/atomic/sigstore
    set -e # enable fail on error
}

teardown () {
    set +e # disable fail on error
    ${ATOMIC} trust default accept
    ${ATOMIC} trust delete localhost:5001
    docker stop atomic-test-registry
    docker rm atomic-test-registry
    docker rmi localhost:5001/atomic-test-sign:latest
    set -e # enable fail on error
}
# Utilize exit traps for cleanup wherever possible. Additional cleanup
# logic can be added to a "cleanup stack", by cascading function calls
# within traps. See tests/integration/test_mount.sh for an example.
trap teardown EXIT

setup

# The test is considered to pass if it exits with zero status. Any other
# exit status is considered failure.

OUTPUT=$(GNUPGHOME=${WORK_DIR} ${ATOMIC} push --username="" --password="" --sign-by B75DB8C20872A524E3F801E08574E36B1DA0F21D localhost:5001/atomic-test-sign:latest)
if [[ $? -ne 0 ]]; then
    exit 1
fi

${ATOMIC} trust default reject
${ATOMIC} trust show
${ATOMIC} trust show --raw

# Expected fail
set +e # disable fail on error
#false
OUTPUT=$(${ATOMIC} pull docker.io/library/busybox)
if [[ $? -eq 0 ]]; then
    exit 1
fi
set -e # enable fail on error

OUTPUT=$(${ATOMIC} pull localhost:5001/atomic-test-sign:latest)
if [[ $? -ne 0 ]]; then
    exit 1
fi

teardown
