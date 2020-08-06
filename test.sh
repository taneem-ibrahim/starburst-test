#!/bin/bash

STORAGE_CLASS=${STORAGE_CLASS:-}

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

os::test::junit::declare_suite_start "$MY_SCRIPT"

checkCreate() {
  local corename
  local frontname

  # Make sure we've only got 1 (in case we ran in a dirty namespace)
  os::cmd::try_until_text "oc get pods --no-headers -l app.kubernetes.io/name=perceptilabs-core 2> /dev/null | wc -l" '^1$'
  os::cmd::try_until_text "oc get pods --no-headers -l app.kubernetes.io/name=perceptilabs-frontend 2> /dev/null | wc -l" '^1$'

  # Make sure the lists are fully populaed, sometimes "items" is not immediately populated
  os::cmd::try_until_success "oc get pod -l app.kubernetes.io/name=perceptilabs-core -o jsonpath='{.items[0].metadata.name}'"
  corename=$(oc get pod -l app.kubernetes.io/name=perceptilabs-core -o jsonpath="{.items[0].metadata.name}")
  os::cmd::try_until_success "oc get pod -l app.kubernetes.io/name=perceptilabs-frontend -o jsonpath='{.items[0].metadata.name}'"
  frontname=$(oc get pod -l app.kubernetes.io/name=perceptilabs-frontend -o jsonpath="{.items[0].metadata.name}")

  os::cmd::try_until_text "oc get pod $corename -o jsonpath='{.status.containerStatuses[?(@.name==\"core\")].ready}'" "true"
  os::cmd::try_until_text "oc get pod $frontname -o jsonpath='{.status.containerStatuses[?(@.name==\"frontend\")].ready}'" "true"
  os::cmd::try_until_success "oc get configmap perceptilabs-license"
  os::cmd::try_until_success "oc get service perceptilabs-core"
  os::cmd::try_until_success "oc get service perceptilabs-frontend"
  os::cmd::try_until_success "oc get route perceptilabs-core"
  os::cmd::try_until_success "oc get route perceptilabs-frontend"

  # If the endpoint list is non-null then services successfully mapped to pods
  os::cmd::try_until_not_text "oc get endpoints perceptilabs-core -o=jsonpath='{.subsets}' | wc -c" '^0$'
  os::cmd::try_until_not_text "oc get endpoints perceptilabs-frontend -o=jsonpath='{.subsets}' | wc -c" '^0$'

  host=$(oc get route perceptilabs-frontend -o jsonpath="{.spec.host}")
  os::cmd::try_until_text "curl $host" "PerceptiLabs"
}

testCreate() {
  os::cmd::expect_success_and_text "oc create -f $MY_DIR/manifests/presto.yaml" 'presto.starburstdata.com/presto-test created'
  os::cmd::try_until_text "oc get pods --no-headers -l instance=presto-test 2>/dev/null | wc -l" '^3$'
}

testDelete() {
    local presto
    local res
    while true; do
        set +e
        presto=$(oc get presto -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        res=$?
        set -e
	if [ "$res" -eq 0 ]; then
            os::cmd::expect_success "oc delete presto $presto"	    
            os::cmd::try_until_text "oc get pods --no-headers -l instance=$presto 2>/dev/null | wc -l" '^0$'
	else
	    break
	fi
    done
  # os::cmd::try_until_failure "oc get configmap perceptilabs-license"
  # os::cmd::try_until_failure "oc get service perceptilabs-core"
  # os::cmd::try_until_failure "oc get service perceptilabs-frontend"
  # os::cmd::try_until_failure "oc get route perceptilabs-core"
  # os::cmd::try_until_failure "oc get route perceptilabs-frontend"
  # os::cmd::try_until_text "oc get perceptilabs --no-headers 2> /dev/null | wc -l" '^0$'
}

# make sure we're not starting with any prestos
set +e
testDelete
set -e

testCreate
testDelete

os::test::junit::declare_suite_end
