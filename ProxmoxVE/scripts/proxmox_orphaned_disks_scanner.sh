#!/usr/bin/env bash
# Copyright (c) angelizer369
# Author: angelizer369
# License: MIT
# https://github.com/angelizer369/knowledge_base/blob/main/LICENSE 

# Description:
# Scans for orphaned/unused disks on all Proxmox storages
# Finds disk volumes that exist but are not attached to any VM/CT

# =================================================================
# Proxmox Orphaned Disks Scanner
# =================================================================

# --- Color Definitions ---
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
L_BLUE=$'\033[1;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

# --- Script Header ---
printf -- "%b" "${L_BLUE}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}
"
printf -- "%b" "${L_BLUE}${BOLD}║              PROXMOX ORPHANED DISKS SCANNER               ║${NC}
"
printf -- "%b" "${L_BLUE}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}

"

# --- Helper Functions ---

# Standardized error exit
failexit() {
    printf -- "%b" "${RED}${BOLD}!!! ERROR: $2 (Code: $1) !!!${NC}
"
    exit "$1"
}

# --- Main Execution ---

# Check for jq
if ! command -v jq &> /dev/null; then
    failexit 1 "jq is required but not installed. Please run 'apt-get install jq'."
fi

# Rescan all disks
printf -- "%b" "${L_BLUE}▶ Running qm disk rescan...${NC}
"
qm disk rescan
printf -- "%b" "${GREEN}✔ Disk rescan complete.${NC}

"

# Get all VMs/CTs
printf -- "%b" "${L_BLUE}▶ Scanning VM/Container Configurations...${NC}
"
GUEST_DATA=$(pvesh get /cluster/resources --type vm --output-format json)

# Temporary file for raw data
UNUSED_TMP_RAW="/dev/shm/unused_list_tmp"
rm -f "$UNUSED_TMP_RAW"

found_unused_in_config=0
global_idx=0

# Parse guest data
while IFS=$'\t' read -r vmid node type_raw name status; do

    if [[ "$type_raw" == "qemu" ]]; then
        conf_file="/etc/pve/nodes/$node/qemu-server/$vmid.conf"
        type="qm"
    elif [[ "$type_raw" == "lxc" ]]; then
        conf_file="/etc/pve/nodes/$node/lxc/$vmid.conf"
        type="pct"
    else
        continue
    fi

    if [[ -f "$conf_file" ]]; then
        # Extract unused disk config lines
        while read -r disk_line; do
            [[ -z "$disk_line" ]] && continue
            
            # Check for unused entries
            if [[ "$disk_line" =~ ^unused ]]; then
                key=$(echo "$disk_line" | cut -d: -f1)
                vol=$(echo "$disk_line" | cut -d: -f2-)
                
                # Write to temp file: node|type|vmid|name|status|key|vol
                printf "%s|%s|%s|%s|%s|%s|%s\n" "$node" "$type" "$vmid" "${name}" "$status" "$key" "$vol" >> "$UNUSED_TMP_RAW"
                found_unused_in_config=1
            fi
        done < <(grep -E "^unused[0-9]*:" "$conf_file")
    fi
done < <(echo "$GUEST_DATA" | jq -r '.[] | [.vmid, .node, .type, .name, .status] | @tsv')

# Display Results
if [[ $found_unused_in_config -eq 0 ]]; then
    printf -- "%b" "${GREEN}✔ No unused disk entries found in configs.${NC}
"
else
    # Sort by node then by VMID (numeric)
    sort -t'|' -k1,1 -k3,3n "$UNUSED_TMP_RAW" > "${UNUSED_TMP_RAW}.sorted"

    # Grouping variables
    declare -A vm_disks
    declare -A vm_counts
    declare -A vm_name
    declare -A vm_status
    declare -A vm_type
    declare -A node_vms
    declare -A node_disk_count
    nodes_order=()

    # Process sorted data
    while IFS='|' read -r node type vmid name status key vol; do
        vm_key="$node|$vmid"
        
        # Track node order
        if [[ -z "${node_vms[$node]}" ]]; then
            nodes_order+=("$node")
        fi
        
        # Append vmid to node's vm list (ensure uniqueness)
        if [[ ! " ${node_vms[$node]} " =~ " $vmid " ]]; then
            node_vms[$node]="${node_vms[$node]} $vmid"
        fi
        
        # Append disk info to VM
        vm_disks[$vm_key]="${vm_disks[$vm_key]}${key}|${vol}\n"
        vm_counts[$vm_key]="$(( ${vm_counts[$vm_key]:-0} + 1 ))"
        
        # Track metadata
        vm_name[$vm_key]="$name"
        vm_status[$vm_key]="$status"
        vm_type[$vm_key]="$type"
        
        # Node totals
        node_disk_count[$node]=$(( ${node_disk_count[$node]:-0} + 1 ))
    done < "${UNUSED_TMP_RAW}.sorted"

    # Output Tree
    printf -- "\n"
    global_idx=0
    for node in "${nodes_order[@]}"; do
        node_total_disks=${node_disk_count[$node]:-0}
        printf "${L_BLUE}${BOLD}Node: %-12s  (%2d unused disks)${NC}\n" "$node" "$node_total_disks"

        vmids=( ${node_vms[$node]} )
        vm_count=${#vmids[@]}
        
        for j in "${!vmids[@]}"; do
            vmid=${vmids[$j]}
            vm_key="$node|$vmid"
            type=${vm_type[$vm_key]}
            name=${vm_name[$vm_key]}
            status=${vm_status[$vm_key]}

            # Colored status
            d_status="$status"
            [[ "$status" == "running" ]] && d_status="${GREEN}running${NC}"
            [[ "$status" == "stopped" ]] && d_status="${RED}stopped${NC}"

            count=${vm_counts[$vm_key]:-0}
            if [ "$count" -eq 1 ]; then
                disks_label="1 disk"
            else
                disks_label="$count disks"
            fi

            # Tree branch for VM
            if [ "$j" -lt $((vm_count - 1)) ]; then
                vm_branch="├─"
                vm_indent_prefix="│  "
            else
                vm_branch="└─"
                vm_indent_prefix="   "
            fi

            printf "%s ${BOLD}%-4s %-6s %-12s %-12s %s${NC}\n" "$vm_branch" "[$type]" "$vmid" "$disks_label" "$d_status" "${name:0:30}"

            # Output disks for this VM
            IFS=$'\n' read -r -d '' -a lines <<< "$(printf "%b" "${vm_disks[$vm_key]}")" || true
            for i in "${!lines[@]}"; do
                line="${lines[$i]}"
                [[ -z "$line" ]] && continue
                key=$(echo "$line" | cut -d'|' -f1)
                vol=$(echo "$line" | cut -d'|' -f2)

                ((global_idx++))
                if [ "$i" -lt $((${#lines[@]} - 1)) ]; then
                    disk_branch="├─"
                else
                    disk_branch="└─"
                fi
                
                # Format: Indent [IDX] Branch Key Volume
                printf "%s [${YELLOW}%3d${NC}] %s %-10s %s\n" "$vm_indent_prefix" "$global_idx" "$disk_branch" "$key" "$vol"
            done
        done
    done
    
    # Clean up temp files
    rm -f "${UNUSED_TMP_RAW}.sorted" "$UNUSED_TMP_RAW"
fi

printf -- "\n%b" "${L_BLUE}▶ Scan Complete${NC}\n\n"
printf -- "${GREEN}${BOLD}✔ Unused disk check finished.${NC}\n"
