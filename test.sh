#!/bin/bash

STORAGE_CLASS=${STORAGE_CLASS:-}

source $TEST_DIR/common

MY_DIR=$(readlink -f `dirname "${BASH_SOURCE[0]}"`)

os::test::junit::declare_suite_start "$MY_SCRIPT"

testCreate() {
    local coordinator
    local worker
    local jpath

    os::cmd::expect_success_and_text "oc create -f $MY_DIR/manifests/presto.yaml" 'presto.starburstdata.com/presto-test created'
    os::cmd::try_until_text "oc get pods --no-headers -l instance=presto-test 2>/dev/null | wc -l" '^3$'

    # Make sure the pods are all running
    # Make sure the lists are fully populated first, sometimes "items" is not immediately populated
    os::cmd::try_until_success "oc get pod -l instance=presto-test -l role=coordinator -o jsonpath='{.items[0].metadata.name}'"
    coordinator=$(oc get pod -l instance=presto-test -l role=coordinator -o jsonpath='{.items[0].metadata.name}')
    os::cmd::try_until_text "oc get pod $coordinator -o jsonpath='{.status.phase}'" "Running"
    for idx in 0 1
    do
        os::cmd::try_until_success "oc get pod -l instance=presto-test -l role=worker -o jsonpath='{.items[$idx].metadata.name}'"
        jpath="{.items[$idx].metadata.name}"
        worker=$(oc get pod -l instance=presto-test -l role=worker -o jsonpath=\'$jpath\')
        os::cmd::try_until_text "oc get pod $coordinator -o jsonpath='{.status.phase}'" "Running"
    done

    # check for config maps
    os::cmd::expect_success_and_text "oc get cm --no-headers -l instance=presto-test -l role=catalogs 2>/dev/null | wc -l" '^1$'
    os::cmd::expect_success_and_text "oc get cm --no-headers -l instance=presto-test -l role=configuration 2>/dev/null | wc -l" '^1$'

    # check for service and successful mapping of endpoints
    os::cmd::try_until_success "oc get service presto-test"
    os::cmd::try_until_not_text "oc get endpoints presto-test -o=jsonpath='{.subsets}' | wc -c" '^0$'
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
        os::cmd::expect_success_and_text "oc get cm --no-headers -l instance=$presto 2>/dev/null | wc -l" '^0$'
        os::cmd::try_until_failure "oc get service $presto"
    done
}

# make sure we're not starting with any prestos
set +e
testDelete
set -e

testCreate
testDelete

os::test::junit::declare_suite_end
