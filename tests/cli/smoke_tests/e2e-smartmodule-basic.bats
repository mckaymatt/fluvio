#!/usr/bin/env bats

TEST_HELPER_DIR="$BATS_TEST_DIRNAME/../test_helper"
export TEST_HELPER_DIR

load "$TEST_HELPER_DIR"/tools_check.bash
load "$TEST_HELPER_DIR"/fluvio_dev.bash
load "$TEST_HELPER_DIR"/bats-support/load.bash
load "$TEST_HELPER_DIR"/bats-assert/load.bash

setup_file() {
    # Compile the smart-module examples
    pushd "$BATS_TEST_DIRNAME/../../.." && make build_smartmodules && popd
    SMARTMODULE_BUILD_DIR="$BATS_TEST_DIRNAME/../../../crates/fluvio-smartmodule/examples/target/wasm32-unknown-unknown/release/"
    export SMARTMODULE_BUILD_DIR
    
}

@test "smart-module map" {
    # Load the smart-module
    SMARTMODULE_NAME="uppercase"
    export SMARTMODULE_NAME
    run timeout 15s "$FLUVIO_BIN" smart-module create $SMARTMODULE_NAME --wasm-file $SMARTMODULE_BUILD_DIR/fluvio_wasm_map.wasm 
    assert_success

    # Create topic
    TOPIC_NAME="$(random_string)"
    export TOPIC_NAME
    run timeout 15s "$FLUVIO_BIN" topic create "$TOPIC_NAME"
    assert_success

    # Produce to topic
    TEST_MESSAGE="$(random_string 10)"
    export TEST_MESSAGE
    run bash -c 'echo "$TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME"'
    assert_success

    # Consume from topic
    EXPECTED_OUTPUT="${TEST_MESSAGE^^}"
    export EXPECTED_OUTPUT
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --map "$SMARTMODULE_NAME"

    assert_output --partial "$EXPECTED_OUTPUT"
    assert_success

    # Consume from topic with --smartmodule
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --smartmodule "$SMARTMODULE_NAME"
    assert_output --partial "$EXPECTED_OUTPUT"
    assert_success

    # Delete topic
    run timeout 15s "$FLUVIO_BIN" topic delete "$TOPIC_NAME"
    assert_success

    # Delete smart-module
    run timeout 15s "$FLUVIO_BIN" smart-module delete "$SMARTMODULE_NAME"
    assert_success
}

@test "smart-module filter" {
    # Load the smart-module
    SMARTMODULE_NAME="contains-a"
    export SMARTMODULE_NAME
    run timeout 15s "$FLUVIO_BIN" smart-module create $SMARTMODULE_NAME --wasm-file $SMARTMODULE_BUILD_DIR/fluvio_wasm_filter.wasm 
    assert_success

    # Create topic
    TOPIC_NAME="$(random_string)"
    export TOPIC_NAME
    run timeout 15s "$FLUVIO_BIN" topic create "$TOPIC_NAME"
    assert_success

    # Produce to topic
    NEGATIVE_TEST_MESSAGE="zzzzzzzzzzzzzz"
    export NEGATIVE_TEST_MESSAGE
    run bash -c 'echo "$NEGATIVE_TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME"'
    assert_success

    TEST_MESSAGE="$(random_string 10)aaa"
    export TEST_MESSAGE
    run bash -c 'echo "$TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME" --compression gzip'
    assert_success

    # Consume from topic and verify we should have 2 entries
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d
    assert_line --index 0 "$NEGATIVE_TEST_MESSAGE"
    assert_line --index 1 "$TEST_MESSAGE"

    # Consume from topic with smart-module and verify we don't see the $NEGATIVE_TEST_MESSAGE
    EXPECTED_OUTPUT="${TEST_MESSAGE}"
    export EXPECTED_OUTPUT
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --filter "$SMARTMODULE_NAME"
    refute_line "$NEGATIVE_TEST_MESSAGE"
    assert_output "$EXPECTED_OUTPUT"

    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --smartmodule "$SMARTMODULE_NAME"
    refute_line "$NEGATIVE_TEST_MESSAGE"
    assert_output "$EXPECTED_OUTPUT"

    # Delete topic
    run timeout 15s "$FLUVIO_BIN" topic delete "$TOPIC_NAME"
    assert_success

    # Delete smart-module
    run timeout 15s "$FLUVIO_BIN" smart-module delete "$SMARTMODULE_NAME"
    assert_success
}

@test "smart-module filter w/ params" {
    # Load the smart-module
    SMARTMODULE_NAME="contains-a-or-param"
    export SMARTMODULE_NAME
    run timeout 15s "$FLUVIO_BIN" smart-module create $SMARTMODULE_NAME --wasm-file $SMARTMODULE_BUILD_DIR/fluvio_wasm_filter_with_parameters.wasm 
    assert_success

    # Create topic
    TOPIC_NAME="$(random_string)"
    export TOPIC_NAME
    run timeout 15s "$FLUVIO_BIN" topic create "$TOPIC_NAME"
    assert_success

    # Produce to topic
    NEGATIVE_TEST_MESSAGE="xxxxx"
    export NEGATIVE_TEST_MESSAGE
    run bash -c 'echo "$NEGATIVE_TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME"'
    assert_success

    DEFAULT_PARAM_MESSAGE="aaaaa"
    export DEFAULT_PARAM_MESSAGE
    run bash -c 'echo "$DEFAULT_PARAM_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME"'
    assert_success

    TEST_PARAM_MESSAGE="zzzzz"
    export TEST_PARAM_MESSAGE
    run bash -c 'echo "$TEST_PARAM_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME"'
    assert_success

    # Consume from topic and verify we should have 3 entries
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d
    assert_line --index 0 "$NEGATIVE_TEST_MESSAGE"
    assert_line --index 1 "$DEFAULT_PARAM_MESSAGE"
    assert_line --index 2 "$TEST_PARAM_MESSAGE"

    # Consume from topic with smart-module and verify we don't see the $NEGATIVE_TEST_MESSAGE
    EXPECTED_OUTPUT="${DEFAULT_PARAM_MESSAGE}"
    export EXPECTED_OUTPUT
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --filter "$SMARTMODULE_NAME"
    refute_line --partial "$NEGATIVE_TEST_MESSAGE"
    refute_line --partial "$TEST_PARAM_MESSAGE"
    assert_output "$EXPECTED_OUTPUT"


    EXPECTED_OUTPUT="${TEST_PARAM_MESSAGE}"
    export EXPECTED_OUTPUT
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --filter "$SMARTMODULE_NAME" --extra-params key=z
    refute_line --partial "$NEGATIVE_TEST_MESSAGE"
    refute_line --partial "$DEFAULT_PARAM_MESSAGE"
    assert_output "$EXPECTED_OUTPUT"

    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --smartmodule "$SMARTMODULE_NAME" --extra-params key=z
    refute_line --partial "$NEGATIVE_TEST_MESSAGE"
    refute_line --partial "$DEFAULT_PARAM_MESSAGE"
    assert_output "$EXPECTED_OUTPUT"

    # Delete topic
    run timeout 15s "$FLUVIO_BIN" topic delete "$TOPIC_NAME"
    assert_success

    # Delete smart-module
    run timeout 15s "$FLUVIO_BIN" smart-module delete "$SMARTMODULE_NAME"
    assert_success
}

@test "smart-module filter-map" {
    # Load the smart-module
    SMARTMODULE_NAME="divide-even-by-2"
    export SMARTMODULE_NAME
    run timeout 15s "$FLUVIO_BIN" smart-module create $SMARTMODULE_NAME --wasm-file $SMARTMODULE_BUILD_DIR/fluvio_wasm_filter_map.wasm 
    assert_success

    # Create topic
    TOPIC_NAME="$(random_string)"
    export TOPIC_NAME
    run timeout 15s "$FLUVIO_BIN" topic create "$TOPIC_NAME"
    assert_success

    # Produce to topic
    NEGATIVE_TEST_MESSAGE="37"
    export NEGATIVE_TEST_MESSAGE
    run bash -c 'echo "$NEGATIVE_TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME"'
    assert_success

    TEST_MESSAGE="100"
    export TEST_MESSAGE
    run bash -c 'echo "$TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME" --compression snappy'
    assert_success

    # Consume from topic and verify we should have 2 entries
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d
    assert_line --index 0 "$NEGATIVE_TEST_MESSAGE"
    assert_line --index 1 "$TEST_MESSAGE"

    # Consume from topic with smart-module and verify we don't see the $NEGATIVE_TEST_MESSAGE
    EXPECTED_OUTPUT="${TEST_MESSAGE}"
    export EXPECTED_OUTPUT
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --filter-map "$SMARTMODULE_NAME"
    refute_line "$NEGATIVE_TEST_MESSAGE"
    assert_output "$((EXPECTED_OUTPUT/2))"

    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --smartmodule "$SMARTMODULE_NAME"
    refute_line "$NEGATIVE_TEST_MESSAGE"
    assert_output "$((EXPECTED_OUTPUT/2))"

    # Delete topic
    run timeout 15s "$FLUVIO_BIN" topic delete "$TOPIC_NAME"
    assert_success

    # Delete smart-module
    run timeout 15s "$FLUVIO_BIN" smart-module delete "$SMARTMODULE_NAME"
    assert_success
}

@test "smart-module array-map" {
    # Load the smart-module
    SMARTMODULE_NAME="json-object-flatten"
    export SMARTMODULE_NAME
    run timeout 15s "$FLUVIO_BIN" smart-module create $SMARTMODULE_NAME --wasm-file $SMARTMODULE_BUILD_DIR/fluvio_wasm_array_map_object.wasm 

    assert_success

    # Create topic
    TOPIC_NAME="$(random_string)"
    export TOPIC_NAME
    run timeout 15s "$FLUVIO_BIN" topic create "$TOPIC_NAME"
    assert_success

    # Produce to topic
    FULL_TEST_MESSAGE='{"a": "Apple", "b": "Banana", "c": "Cranberry"}'
    export FULL_TEST_MESSAGE
    FIRST_MESSAGE='"Apple"'
    export FIRST_MESSAGE
    SECOND_MESSAGE='"Banana"'
    export SECOND_MESSAGE
    THIRD_MESSAGE='"Cranberry"'
    export THIRD_MESSAGE
    run bash -c 'echo "$FULL_TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME" --compression lz4'
    assert_success

    # Consume from topic and verify we should have the json message
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d
    assert_output "$FULL_TEST_MESSAGE"

    # Consume from topic with smart-module and verify we don't see the $NEGATIVE_TEST_MESSAGE
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --array-map "$SMARTMODULE_NAME"
    assert_line --index 0 "$FIRST_MESSAGE"
    assert_line --index 1 "$SECOND_MESSAGE"
    assert_line --index 2 "$THIRD_MESSAGE"

    # Consume from topic with smart-module and verify we don't see the $NEGATIVE_TEST_MESSAGE
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --smartmodule "$SMARTMODULE_NAME"
    assert_line --index 0 "$FIRST_MESSAGE"
    assert_line --index 1 "$SECOND_MESSAGE"
    assert_line --index 2 "$THIRD_MESSAGE"

    # Delete topic
    run timeout 15s "$FLUVIO_BIN" topic delete "$TOPIC_NAME"
    assert_success

    # Delete smart-module
    run timeout 15s "$FLUVIO_BIN" smart-module delete "$SMARTMODULE_NAME"
    assert_success
}

@test "smart-module aggregate" {
    # Load the smart-module
    SMARTMODULE_NAME="concat-strings"
    export SMARTMODULE_NAME
    run timeout 15s "$FLUVIO_BIN" smart-module create $SMARTMODULE_NAME --wasm-file $SMARTMODULE_BUILD_DIR/fluvio_wasm_aggregate.wasm 
    assert_success

    # Create topic
    TOPIC_NAME="$(random_string)"
    export TOPIC_NAME
    run timeout 15s "$FLUVIO_BIN" topic create "$TOPIC_NAME"
    assert_success

    # Produce to topic
    TEST_MESSAGE_1="$(random_string 10)"
    export TEST_MESSAGE_1
    run bash -c 'echo "$TEST_MESSAGE_1" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME"'
    assert_success

    TEST_MESSAGE_2="$(random_string 10)"
    export TEST_MESSAGE_2
    run bash -c 'echo "$TEST_MESSAGE_2" | timeout 15s "$FLUVIO_BIN" produce "$TOPIC_NAME"'
    assert_success

    # Consume from topic
    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --aggregate "$SMARTMODULE_NAME"
    assert_line --index 0 "$TEST_MESSAGE_1"
    assert_line --index 1 "$TEST_MESSAGE_1$TEST_MESSAGE_2"

    run timeout 15s "$FLUVIO_BIN" consume "$TOPIC_NAME" -B -d --smartmodule "$SMARTMODULE_NAME"
    assert_line --index 0 "$TEST_MESSAGE_1"
    assert_line --index 1 "$TEST_MESSAGE_1$TEST_MESSAGE_2"

    # Delete topic
    run timeout 15s "$FLUVIO_BIN" topic delete "$TOPIC_NAME"
    assert_success

    # Delete smart-module
    run timeout 15s "$FLUVIO_BIN" smart-module delete "$SMARTMODULE_NAME"
    assert_success
}

@test "smart-module join" {
    # Load the smart-module
    SMARTMODULE_NAME="join-sum"
    export SMARTMODULE_NAME
    run timeout 15s "$FLUVIO_BIN" smart-module create $SMARTMODULE_NAME --wasm-file $SMARTMODULE_BUILD_DIR/fluvio_wasm_join.wasm 
    assert_success

    # Create topic
    MAIN_TOPIC_NAME="$(random_string)"
    export MAIN_TOPIC_NAME
    run timeout 15s "$FLUVIO_BIN" topic create "$MAIN_TOPIC_NAME"
    assert_success

    JOIN_TOPIC_NAME="$(random_string)"
    export JOIN_TOPIC_NAME
    run timeout 15s "$FLUVIO_BIN" topic create "$JOIN_TOPIC_NAME"
    assert_success

    # Produce to join topic first
    #R1_TEST_MESSAGE="$RANDOM"
    R1_TEST_MESSAGE="1"
    export R1_TEST_MESSAGE
    run bash -c 'echo "$R1_TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$JOIN_TOPIC_NAME"'
    assert_success

    # Then to main topic
    #L1_TEST_MESSAGE="$RANDOM"
    L1_TEST_MESSAGE="2"
    export L1_TEST_MESSAGE
    run bash -c 'echo "$L1_TEST_MESSAGE" | timeout 15s "$FLUVIO_BIN" produce "$MAIN_TOPIC_NAME"'
    assert_success

    # Consume from topic
    EXPECTED_OUTPUT_0="$((R1_TEST_MESSAGE+L1_TEST_MESSAGE))"
    export EXPECTED_OUTPUT_0
    run timeout 15s "$FLUVIO_BIN" consume "$MAIN_TOPIC_NAME" -B -d --join "$SMARTMODULE_NAME" --join-topic $JOIN_TOPIC_NAME
    assert_output "$EXPECTED_OUTPUT_0"

    run timeout 15s "$FLUVIO_BIN" consume "$MAIN_TOPIC_NAME" -B -d --smartmodule "$SMARTMODULE_NAME" --join-topic $JOIN_TOPIC_NAME
    assert_output "$EXPECTED_OUTPUT_0"

    # Delete topics
    run timeout 15s "$FLUVIO_BIN" topic delete "$MAIN_TOPIC_NAME"
    assert_success
    run timeout 15s "$FLUVIO_BIN" topic delete "$JOIN_TOPIC_NAME"
    assert_success

    # Delete smart-module
    run timeout 15s "$FLUVIO_BIN" smart-module delete "$SMARTMODULE_NAME"
    assert_success
}
