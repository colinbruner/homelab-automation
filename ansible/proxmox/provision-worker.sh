#!/usr/bin/env bash

ansible-playbook \
    -i inventory/hosts.yml \
    "$@" \
    provision-worker.yml
