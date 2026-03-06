#!/usr/bin/env bash

ansible-playbook \
    -i inventory/hosts.yml \
    "$@" \
    upgrade-8to9.yml
