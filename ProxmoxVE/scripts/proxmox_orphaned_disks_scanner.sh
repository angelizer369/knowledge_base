#!/usr/bin/env bash
# Copyright (c) angelizer369
# Author: angelizer369
# License: MIT
# https://github.com/angelizer369/knowledge_base/blob/main/LICENSE 

# Description:
# Scans for orphaned/unused disks on all Proxmox storages
# Finds disk volumes that exist but are not attached to any VM/CT
# Provides an interactive menu to delete them safely

# =================================================================
# Proxmox Orphaned Disks Scanner
# =================================================================

# --- Color Definitions ---
# These variables hold the ANSI escape codes for different colors and text styles.
# This allows for formatted and colorized output in the terminal.
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
L_BLUE=$'\033[1;34m'
BOLD=$'\033[1m'
NC=$'\033[0m' # No Color

# --- Script Header ---
# Prints a decorative header for the script.
printf -- "%b" "${L_BLUE}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}
"
printf -- "%b" "${L_BLUE}${BOLD}║              PROXMOX ORPHANED DISKS SCANNER               ║${NC}
"
printf -- "%b" "${L_BLUE}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}

"

# --- Helper Functions ---

# Standardized error exit function.
# It prints a formatted error message and exits the script with a given status code.
# $1: Exit code
# $2: Error message
failexit() {
    printf -- "%b" "${RED}${BOLD}!!! ERROR: $2 (Code: $1) !!!${NC}
"
    exit "$1"
}

# --- Main Execution ---

# Check if 'jq' is installed, as it is required for parsing JSON output from pvesh.
if ! command -v jq &> /dev/null; then
    failexit 1 "jq is required but not installed. Please run 'apt-get install jq'."
fi

# --- Cluster-wide Disk Rescan ---
# To get the most up-to-date storage information, this section rescans all storages on every online node in the cluster.
printf -- "%b" "${L_BLUE}▶ Rescanning disks on all cluster nodes...${NC}\n"

for NODE in $(pvesh get /nodes --output-format json | jq -r '.[].node'); do
  printf "== ${YELLOW}%s${NC} ==\n" "$NODE"

  ssh root@$NODE '
    echo "[qm] disk rescan"
    qm disk rescan

    echo "[pct] rescan"
    pct rescan
  '
done

printf -- "\n%b" "${GREEN}✔ Cluster-wide disk rescan complete.${NC}\n\n"

# Get a list of all resources of type 'vm' (which includes VMs and CTs) in JSON format.
printf -- "%b" "${L_BLUE}▶ Scanning VM/Container Configurations...${NC}
"
GUEST_DATA=$(pvesh get /cluster/resources --type vm --output-format json)

# Define a temporary file to store raw data about unused disks.
# Using /dev/shm (shared memory) is fast as it's a tmpfs.
UNUSED_TMP_RAW="/dev/shm/unused_list_tmp"
ORPHANED_DISK_LIST="/dev/shm/orphaned_disk_list"
# Ensure the temporary file from a previous run is removed.
rm -f "$UNUSED_TMP_RAW" "$ORPHANED_DISK_LIST"

# Flags and counters initialization.
found_unused_in_config=0
global_idx=0

# Parse the JSON data from GUEST_DATA.
# The loop reads tab-separated values extracted by jq.
while IFS=$'\t' read -r vmid node type_raw name status; do

    # Determine the configuration file path based on the guest type (qemu for VM, lxc for Container).
    if [[ "$type_raw" == "qemu" ]]; then
        conf_file="/etc/pve/nodes/$node/qemu-server/$vmid.conf"
        type="qm"
    elif [[ "$type_raw" == "lxc" ]]; then
        conf_file="/etc/pve/nodes/$node/lxc/$vmid.conf"
        type="ct"
    else
        # Skip any other resource types.
        continue
    fi

    # Check if the configuration file exists.
    if [[ -f "$conf_file" ]]; then
        # Search for lines in the config file that start with "unused" followed by digits.
        # These lines define disks that are not currently attached to the VM/CT.
        while read -r disk_line; do
            # Skip empty lines.
            [[ -z "$disk_line" ]] && continue
            
            # Check if the line matches the pattern for an unused disk.
            if [[ "$disk_line" =~ ^unused ]]; then
                # Extract the key (e.g., "unused0") and the volume identifier.
                key=$(echo "$disk_line" | cut -d: -f1)
                vol=$(echo "$disk_line" | cut -d: -f2-)
                
                # Write the found information to the temporary file in a pipe-separated format.
                # Format: node|type|vmid|name|status|key|vol
                printf "%s|%s|%s|%s|%s|%s|%s\n" "$node" "$type" "$vmid" "${name}" "$status" "$key" "$vol" >> "$UNUSED_TMP_RAW"
                found_unused_in_config=1
            fi
        done < <(grep -E "^unused[0-9]*:" "$conf_file")
    fi
done < <(echo "$GUEST_DATA" | jq -r '.[] | [.vmid, .node, .type, .name, .status] | @tsv')

# --- Display Results ---
# Check if any unused disk entries were found in the configuration files.
if [[ $found_unused_in_config -eq 0 ]]; then
    printf -- "%b" "${GREEN}✔ No unused disk entries found in configs.${NC}
"
else
    # Sort the temporary file first by node, and then numerically by VMID for structured output.
    sort -t'|' -k1,1 -k3,3n "$UNUSED_TMP_RAW" > "${UNUSED_TMP_RAW}.sorted"

    # --- Grouping and Data Preparation for Display ---
    # Using associative arrays to group disks by VM and VMs by node.
    declare -A vm_disks          # Stores disk lines for each VM
    declare -A vm_counts         # Stores count of unused disks per VM
    declare -A vm_name           # Stores the name of the VM
    declare -A vm_status         # Stores the running status of the VM
    declare -A vm_type           # Stores the type of the VM (qm/pct)
    declare -A node_vms          # Stores a list of VMIDs for each node
    declare -A node_disk_count   # Stores total count of unused disks per node
    nodes_order=()               # Stores the order of nodes to be printed

    # Process the sorted data file to populate the associative arrays.
    while IFS='|' read -r node type vmid name status key vol; do
        vm_key="$node|$vmid"
        
        # Track the order of nodes as they appear.
        if [[ -z "${node_vms[$node]}" ]]; then
            nodes_order+=("$node")
        fi
        
        # Append vmid to the node's vm list, ensuring uniqueness.
        if [[ ! " ${node_vms[$node]} " =~ " $vmid " ]]; then
            node_vms[$node]="${node_vms[$node]} $vmid"
        fi
        
        # Append disk info to the corresponding VM.
        vm_disks[$vm_key]="${vm_disks[$vm_key]}${key}|${vol}\n"
        # Increment the disk count for the VM.
        vm_counts[$vm_key]="$(( ${vm_counts[$vm_key]:-0} + 1 ))"
        
        # Store metadata for the VM.
        vm_name[$vm_key]="$name"
        vm_status[$vm_key]="$status"
        vm_type[$vm_key]="$type"
        
        # Increment the total disk count for the node.
        node_disk_count[$node]=$(( ${node_disk_count[$node]:-0} + 1 ))
    done < "${UNUSED_TMP_RAW}.sorted"

    # --- Output Tree ---
    # Generates a tree-like structured output of the found unused disks.
    printf -- "\n"
    global_idx=0
    # Iterate through each node in the order they were found.
    for node in "${nodes_order[@]}"; do
        node_total_disks=${node_disk_count[$node]:-0}
        # Print the node name and the total count of unused disks on it.
        printf "${L_BLUE}${BOLD}Node: %-12s  (%2d unused disks)${NC}\n" "$node" "$node_total_disks"

        # Get the list of VMIDs for the current node.
        vmids=( ${node_vms[$node]} )
        vm_count=${#vmids[@]}
        
        # Iterate through each VMID associated with the current node.
        for j in "${!vmids[@]}"; do
            vmid=${vmids[$j]}
            vm_key="$node|$vmid"
            type=${vm_type[$vm_key]}
            name=${vm_name[$vm_key]}
            status=${vm_status[$vm_key]}

            # Colorize the status for better readability.
            d_status="$status"
            [[ "$status" == "running" ]] && d_status="${GREEN}running${NC}"
            [[ "$status" == "stopped" ]] && d_status="${RED}stopped${NC}"

            # Create a label for the number of disks.
            count=${vm_counts[$vm_key]:-0}
            if [ "$count" -eq 1 ]; then
                disks_label="1 disk"
            else
                disks_label="$count disks"
            fi

            # Determine the tree branch characters for the VM entry.
            # The last VM under a node gets a different character.
            if [ "$j" -lt $((vm_count - 1)) ]; then
                vm_branch="├─"
                vm_indent_prefix="│  "
            else
                vm_branch="└─"
                vm_indent_prefix="   "
            fi

            # Print the VM information line.
            printf "%s ${BOLD}%-4s %-6s %-12s %-12s %s${NC}\n" "$vm_branch" "[$type]" "$vmid" "$disks_label" "$d_status" "${name:0:30}"

            # Output the unused disks for this VM.
            IFS=$'\n' read -r -d '' -a lines <<< "$(printf "%b" "${vm_disks[$vm_key]}")" || true
            for i in "${!lines[@]}"; do
                line="${lines[$i]}"
                [[ -z "$line" ]] && continue
                key=$(echo "$line" | cut -d'|' -f1)
                vol=$(echo "$line" | cut -d'|' -f2)

                ((global_idx++))
                echo "$global_idx $node $type $vmid $key $vol" >> "$ORPHANED_DISK_LIST"
                # Determine the tree branch characters for the disk entry.
                if [ "$i" -lt $((${#lines[@]} - 1)) ]; then
                    disk_branch="├─"
                else
                    disk_branch="└─"
                fi
                
                # Format and print the disk information line.
                # Format: Indent [IDX] Branch Key Volume
                printf "%s [${YELLOW}%3d${NC}] %s %-10s %s\n" "$vm_indent_prefix" "$global_idx" "$disk_branch" "$key" "$vol"
            done
        done
    done
    
    # --- Deletion Menu ---
    printf -- "\n%b" "${YELLOW}------------------------------------------------------------------${NC}\n"
    printf -- "%b" "${L_BLUE}${BOLD}▶ Orphaned Disks Menu${NC}\n"
    
    # Exit if no disks were indexed
    if [[ ! -s "$ORPHANED_DISK_LIST" ]]; then
        printf -- "%b" "${GREEN}✔ No disks available for deletion.${NC}\n"
    else
        echo -e "  [${YELLOW}1${NC}] Delete ALL listed disks"
        echo -e "  [${YELLOW}2${NC}] Delete specific disks by ID"
        echo -e "  [${YELLOW}3${NC}] Exit"

        while true; do
            read -p "Selection [1-3]: " del_sel
            if [[ "$del_sel" =~ ^[1-3]$ ]]; then
                break
            else
                printf -- "%b" "${RED}Invalid selection. Please enter a number between 1 and 3.${NC}\n"
            fi
        done

        if [[ "$del_sel" == "3" ]]; then
            printf -- "%b" "${YELLOW}Aborted by user.${NC}\n"
        else
            selected_ids=""
            if [[ "$del_sel" == "2" ]]; then
                while true; do
                    read -p "Enter Disk IDs to delete (space separated): " selected_ids
                    if [[ "$selected_ids" =~ ^[0-9\ ]+$ ]]; then
                        break
                    else
                        printf -- "%b" "${RED}Invalid input. Please enter only space-separated numbers.${NC}\n"
                    fi
                done
            fi

            echo -e "\nProcessing Mode:"
            echo -e "  [${YELLOW}1${NC}] Bulk (Auto-confirm)"
            echo -e "  [${YELLOW}2${NC}] Interactive (Confirm each)"

            while true; do
                read -p "Selection [1-2]: " mode_sel
                if [[ "$mode_sel" =~ ^[1-2]$ ]]; then
                    break
                else
                    printf -- "%b" "${RED}Invalid selection. Please enter a number between 1 and 2.${NC}\n"
                fi
            done
            
            # --- Deletion Execution ---
            ORPHANED_DISK_LIST_FILTERED="/dev/shm/orphaned_disk_list_filtered"
            rm -f "$ORPHANED_DISK_LIST_FILTERED"

            # Apply filters to disk list
            while read -r idx node type vmid key vol; do
                keep=0
                case "$del_sel" in
                    1) keep=1 ;;
                    2) for id in $selected_ids; do [[ "$id" == "$idx" ]] && keep=1; done ;;
                esac
                [[ "$keep" -eq 1 ]] && echo "$idx $node $type $vmid $key $vol" >> "$ORPHANED_DISK_LIST_FILTERED"
            done < "$ORPHANED_DISK_LIST"

            total_count=$(wc -l < "$ORPHANED_DISK_LIST_FILTERED")
            if [[ "$total_count" -eq 0 ]]; then
                printf -- "\n%b" "${YELLOW}No disks selected for deletion.${NC}\n"
            else
                printf -- "\n%b" "${L_BLUE}▶ Deletion Execution...${NC}\n"
                current=0
                SUCCESS_COUNT=0
                FAILED_COUNT=0
                
                while read -r idx node type vmid key vol; do
                    ((current++))
                    
                    if [[ "$mode_sel" == "2" ]]; then
                        while true; do
                            printf "${YELLOW}Confirm:${NC} Delete [#%s] %s (%s) from %s %s? [y/N]: " "$idx" "$key" "$vol" "$type" "$vmid"
                            read -r ans < /dev/tty
                            ans=$(echo "$ans" | tr '[:upper:]' '[:lower:]')
                            if [[ "$ans" == "y" ]]; then
                                break
                            elif [[ -z "$ans" || "$ans" == "n" ]]; then
                                ans="n" # Default to No
                                break
                            else
                                printf -- "%b" "${RED}Invalid input. Please enter 'y' for yes or 'n' for no.${NC}\n"
                            fi
                        done
                        [[ "$ans" == "n" ]] && { printf "${YELLOW}⏭ Skipped${NC}\n"; continue; }
                    fi

                    echo "----------------------------------------------------------------"
                    printf "Task %d/%d: [%s] Deleting %s from %s %s...\n" "$current" "$total_count" "$node" "$vol" "$type" "$vmid"
                    
                    # --- Deletion Logic ---
                    # Removing the 'unused' entry from the configuration also deletes the underlying disk file.
                    if [[ "$type" == "qm" ]]; then
                        pvesh set "/nodes/$node/qemu/$vmid/config" --delete "$key"
                    else
                        pvesh set "/nodes/$node/lxc/$vmid/config" --delete "$key"
                    fi
                    
                    if [ $? -eq 0 ]; then
                        printf "${GREEN}${BOLD}✔ Config entry '%s' removed and volume deleted successfully.${NC}\n" "$key"
                        ((SUCCESS_COUNT++))
                    else
                        printf "${RED}${BOLD}✖ Failed to remove config entry '%s'.${NC}\n" "$key"
                        ((FAILED_COUNT++))
                    fi

                done < "$ORPHANED_DISK_LIST_FILTERED"

                # --- Summary ---
                echo -e "\n----------------------------------------------------------------"
                echo -e "${L_BLUE}${BOLD}DELETION SUMMARY:${NC}"
                echo -e "  Successful:    ${GREEN}$SUCCESS_COUNT${NC}"
                echo -e "  Failed:        ${RED}$FAILED_COUNT${NC}"
                echo -e "----------------------------------------------------------------"
            fi
            rm -f "$ORPHANED_DISK_LIST_FILTERED"
        fi
    fi
    
    # Clean up the temporary files created during the script execution.
    rm -f "${UNUSED_TMP_RAW}.sorted" "$UNUSED_TMP_RAW" "$ORPHANED_DISK_LIST"
fi

# --- Script Footer ---
printf -- "\n%b" "${L_BLUE}▶ Scan Complete${NC}\n\n"
printf -- "${GREEN}${BOLD}✔ Unused disk check finished.${NC}\n"
