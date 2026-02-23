#!/usr/bin/env bash

REPORT=/tmp/proxmox-capacity-report.txt

    #-vvv \
ansible-playbook \
    -i inventory/hosts.yml \
    --extra-vars "report_output_path=${REPORT}" \
    capacity.yml

echo ""
cat "${REPORT}"
