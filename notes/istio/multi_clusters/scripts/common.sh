#!/bin/bash

function check.command {
    local executable=$1
    command -v "${executable}" >/dev/null 2>&1 || exit.script "${executable} cannot be found in PATH"
}

function check.env {
    local var_name="$1"
    local var_value=${!var_name}
    if [[ -z "$var_value" ]]; then
        print.message "ERROR" "Environment variable $var_name should be set"
        exit 1
    fi
}

function exit.script {
    local error_message=$1
    print.message "ERROR" "${error_message}"
    exit 1
}

function print.message {
    local message_level=$1
    local message_str=$2

    case "${message_level}" in
    "ERROR")
        printf "\n\e[0;31mERROR: \e[m"
        ;;
    "WARNING")
        printf "\n\e[1;33mWARNING: \e[m"
        ;;
    *)
        printf "%s: " "${message_level}"
        ;;
    esac

    printf "%s\n" "${message_str}"
}
