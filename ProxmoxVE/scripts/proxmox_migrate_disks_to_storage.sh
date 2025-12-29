#!/usr/bin/env bash
# Copyright (c) angelizer369
# Author: angelizer369
# License: MIT
# https://github.com/angelizer369/knowledge_base/blob/main/LICENSE 

# Description:
# Migrates disks of virtual machines and containers from one Proxmox storage to another
# using the native Proxmox API (pvesh) for cluster-wide execution.

# =================================================================
# Proxmox Migrate Disks to Storage
# =================================================================

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
L_BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Script Header ---
printf -- "%b" "${L_BLUE}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}\n"
printf -- "%b" "${L_BLUE}${BOLD}║             PROXMOX MIGRATE DISKS TO STORAGE              ║${NC}\n"
printf -- "%b" "${L_BLUE}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}\n\n"

# --- Configuration & Paths ---
LOG_DONE="$HOME/proxmox-migrate-storage.log"
LOG_ERR="$HOME/proxmox-migrate-storage-err.log"
DISK_LIST_RAW="/dev/shm/disklist_raw"
DISK_LIST_FILTERED="/dev/shm/disklist_filtered"

# --- Summary Variables ---
SUCCESS_COUNT=0
FAILED_COUNT=0
TOTAL_BYTES_MOVED=0
TOTAL_TIME_SECONDS=0

# --- Helper Functions ---

# Standardized error exit
failexit() {
    printf -- "%b" "${RED}${BOLD}!!! ERROR: $2 (Code: $1) !!!${NC}\n" | tee -a "$LOG_ERR"
    exit "$1"
}

# Convert various size units to bytes for calculation
to_bytes() {
    local value=$1; local unit=$2
    case $unit in
        T|TB|t) echo "$value * 1024 * 1024 * 1024 * 1024" | bc ;;
        G|GB|g) echo "$value * 1024 * 1024 * 1024" | bc ;;
        M|MB|m) echo "$value * 1024 * 1024" | bc ;;
        K|KB|k) echo "$value * 1024" | bc ;;
        *) echo "$value" ;;
    esac
}

# --- Initialization ---
rm -f "$DISK_LIST_RAW" "$DISK_LIST_FILTERED"

# --- STEP 1: Storage Selection ---
printf -- "%b" "${L_BLUE}▶ Step 1: Selecting Storages...${NC}\n"
mapfile -t storages < <(pvesm status | awk 'NR>1 {print $1}')

# Display storage list starting at index 1
for i in "${!storages[@]}"; do
    printf "  [${YELLOW}%d${NC}] %s\n" "$((i + 1))" "${storages[$i]}"
done

# --- Source Storage Selection with Validation ---
while true; do
    read -p "Select SOURCE Index: " src_idx_input
    # Validate if input is a number and within range
    if [[ "$src_idx_input" =~ ^[0-9]+$ ]] && [ "$src_idx_input" -ge 1 ] && [ "$src_idx_input" -le "${#storages[@]}" ]; then
        SRC_STORAGE=${storages[$((src_idx_input - 1))]}
        break
    else
        printf -- "%b" "${RED}Invalid selection. Please enter a number between 1 and ${#storages[@]}.${NC}\n"
    fi
done

# --- Destination Storage Selection with Validation ---
while true; do
    read -p "Select DESTINATION Index: " dest_idx_input
    # Validate if input is a number, within range, and not the same as source
    if [[ "$dest_idx_input" =~ ^[0-9]+$ ]] && [ "$dest_idx_input" -ge 1 ] && [ "$dest_idx_input" -le "${#storages[@]}" ]; then
        if [ "$dest_idx_input" -ne "$src_idx_input" ]; then
            DEST_STORAGE=${storages[$((dest_idx_input - 1))]}
            break
        else
            printf -- "%b" "${RED}Destination cannot be the same as the source. Please select a different storage.${NC}\n"
        fi
    else
        printf -- "%b" "${RED}Invalid selection. Please enter a number between 1 and ${#storages[@]}.${NC}\n"
    fi
done

[[ -z "$SRC_STORAGE" || -z "$DEST_STORAGE" ]] && failexit 1 "Invalid selection."
[[ "$SRC_STORAGE" == "$DEST_STORAGE" ]] && failexit 2 "Source and Destination are the same."

# --- STEP 2: Cluster-Wide Scan ---
printf -- "\n%b" "${L_BLUE}▶ Step 2: Fetching Guests & Scanning for '$SRC_STORAGE'...${NC}\n"
GUEST_DATA_RAW=$(pvesh get /cluster/resources --type vm --output-format json)

# Table Header
printf "${BOLD}%5s   %-10s %-6s %8s   %-10s %-25s %-10s %8s${NC}\n" "IDX" "NODE" "TYPE" "VMID" "STATUS" "NAME" "DISK" "SIZE"
echo "----------------------------------------------------------------------------------------------------"

global_idx=0

# Parse JSON data and find disks on source storage
while read -r line; do
    vmid=$(echo "$line" | grep -o '"vmid":[0-9]*' | cut -d: -f2)
    node=$(echo "$line" | grep -o '"node":"[^"]*"' | cut -d'"' -f4)
    status=$(echo "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    name=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    type_raw=$(echo "$line" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)

    # Determine guest type and config path
    if [[ "$type_raw" == "qemu" ]]; then
        type="qm"; conf_file="/etc/pve/nodes/$node/qemu-server/$vmid.conf"
    elif [[ "$type_raw" == "lxc" ]]; then
        type="pct"; conf_file="/etc/pve/nodes/$node/lxc/$vmid.conf"
    else continue; fi

    # Check if config contains the source storage
    if [[ -f "$conf_file" ]] && grep -q "$SRC_STORAGE:" "$conf_file"; then
        d_status="$status"
        [[ "$status" == "running" ]] && d_status="${GREEN}running${NC}"
        [[ "$status" == "stopped" ]] && d_status="${RED}stopped${NC}"
        
        # Get individual disk lines (exclude unused disks if needed)
        disk_lines=$(grep "$SRC_STORAGE:" "$conf_file" | grep -v "unused")
        
        while read -r dline; do
            [[ -z "$dline" ]] && continue
            disk=$(echo "$dline" | cut -d: -f1)
            size_str=$(echo "$dline" | grep -o "size=[0-9]*[G|M|K|T]*" | cut -d= -f2)
            [[ -z "$size_str" ]] && continue

            ((global_idx++))
            # Format output: Node alignment fixed to dynamic width
            printf "[${YELLOW}%3d${NC}]  %-10s %-6s ${YELLOW}%8s${NC}   %-19b %-25s %-10s %8s\n" \
                "$global_idx" "$node" "[$type]" "$vmid" "$d_status" "${name:0:24}" "$disk" "$size_str"
            
            # Save data for filtering step
            echo "$global_idx $node $type $vmid $disk $size_str $status" >> "$DISK_LIST_RAW"
        done <<< "$disk_lines"
    fi
done < <(echo "$GUEST_DATA_RAW" | sed 's/},{/}\n{/g' | sed 's/[\[{}]//g')

[[ ! -s "$DISK_LIST_RAW" ]] && failexit 0 "No disks found on '$SRC_STORAGE'."

# --- STEP 3: Migration Filters ---
printf -- "\n%b" "${L_BLUE}▶ Step 3: Select Migration Scope...${NC}\n"
echo -e "  [${YELLOW}1${NC}] All Disks"
echo -e "  [${YELLOW}2${NC}] Only Online Guests (running)"
echo -e "  [${YELLOW}3${NC}] Only Offline Guests (stopped)"
echo -e "  [${YELLOW}4${NC}] Specific Disk IDs (e.g. 1 3 5)"

# --- Filter Selection with Validation ---
while true; do
    read -p "Selection [1-4]: " filter_sel
    if [[ "$filter_sel" =~ ^[1-4]$ ]]; then
        break
    else
        printf -- "%b" "${RED}Invalid selection. Please enter a number between 1 and 4.${NC}\n"
    fi
done

selected_ids=""
if [[ "$filter_sel" == "4" ]]; then
    while true; do
        read -p "Enter Disk IDs (space separated): " selected_ids
        # Validate that input contains only numbers and spaces
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

# --- Mode Selection with Validation ---
while true; do
    read -p "Selection [1-2]: " mode_sel
    if [[ "$mode_sel" =~ ^[1-2]$ ]]; then
        break
    else
        printf -- "%b" "${RED}Invalid selection. Please enter a number between 1 and 2.${NC}\n"
    fi
done

# Apply filters to disk list
while read -r idx node type vmid disk size status; do
    keep=0
    case "$filter_sel" in
        1) keep=1 ;;
        2) [[ "$status" == "running" ]] && keep=1 ;;
        3) [[ "$status" == "stopped" ]] && keep=1 ;;
        4) for id in $selected_ids; do [[ "$id" == "$idx" ]] && keep=1; done ;;
    esac
    [[ "$keep" -eq 1 ]] && echo "$idx $node $type $vmid $disk $size $status" >> "$DISK_LIST_FILTERED"
done < "$DISK_LIST_RAW"

# --- STEP 4: Capacity Check ---
printf -- "\n%b" "${L_BLUE}▶ Step 4: Capacity Check on $DEST_STORAGE...${NC}\n"
[[ ! -s "$DISK_LIST_FILTERED" ]] && failexit 0 "No disks selected."

TOTAL_REQ_BYTES=0
while read -r idx node type vmid disk size status; do
    unit=$(echo "$size" | grep -o "[A-Z]")
    val=$(echo "$size" | grep -o "[0-9]*")
    [[ -n "$val" ]] && db=$(to_bytes "$val" "$unit") && TOTAL_REQ_BYTES=$(echo "$TOTAL_REQ_BYTES + $db" | bc)
done < "$DISK_LIST_FILTERED"

# Get storage free space using pvesm
DEST_FREE_KB=$(pvesm status -storage "$DEST_STORAGE" | awk 'NR>1 {print $6}')
DEST_FREE_BYTES=$(echo "$DEST_FREE_KB * 1024" | bc)
HUM_REQ=$(echo "scale=2; $TOTAL_REQ_BYTES / 1073741824" | bc)
HUM_FREE=$(echo "scale=2; $DEST_FREE_BYTES / 1073741824" | bc)

printf "  Required: ${BOLD}%s GB${NC} | Available: ${BOLD}%s GB${NC}\n" "$HUM_REQ" "$HUM_FREE"
(( $(echo "$TOTAL_REQ_BYTES > $DEST_FREE_BYTES" | bc -l) )) && failexit 5 "Insufficient space!"

# --- STEP 5: Migration Execution ---
printf -- "\n%b" "${L_BLUE}▶ Step 5: Migration Execution...${NC}\n"
total_count=$(wc -l < "$DISK_LIST_FILTERED")
current=0

while read -r idx node type vmid disk size status; do
    ((current++))
    
    # User interaction logic
    if [[ "$mode_sel" == "2" ]]; then
        while true; do
            printf "${YELLOW}Confirm:${NC} Move [#%s] %s (%s) on Node '%s'? [Y/n]: " "$idx" "$disk" "$size" "$node"
            read -r ans < /dev/tty
            ans=$(echo "$ans" | tr '[:upper:]' '[:lower:]')
            # Allow 'y', 'n', or empty input
            if [[ -z "$ans" || "$ans" == "y" || "$ans" == "n" ]]; then
                break
            else
                printf -- "%b" "${RED}Invalid input. Please enter 'y' for yes, 'n' for no, or press Enter for yes.${NC}\n"
            fi
        done
        # If 'n' is entered, skip to the next item
        [[ "$ans" == "n" ]] && { printf "${YELLOW}⏭ Skipped${NC}\n"; continue; }
    fi

    echo "----------------------------------------------------------------"
    printf "Task %d/%d: [%s] Moving %s %s [%s]...\n" "$current" "$total_count" "$node" "$type" "$vmid" "$disk"

    start_time=$(date +%s)

    # Execute migration via Proxmox API (pvesh) for cluster-wide routing
    if [[ "$type" == "qm" ]]; then
        pvesh create /nodes/"$node"/qemu/"$vmid"/move_disk --disk "$disk" --storage "$DEST_STORAGE" --delete 1
    else
        pvesh create /nodes/"$node"/lxc/"$vmid"/move_volume --volume "$disk" --storage "$DEST_STORAGE" --delete 1
    fi

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # Check exit status of the API call and update statistics
    if [ $? -eq 0 ]; then
        printf "${GREEN}${BOLD}✔ Task Finished in %s seconds${NC}\n" "$duration" | tee -a "$LOG_DONE"
        ((SUCCESS_COUNT++))
        TOTAL_TIME_SECONDS=$((TOTAL_TIME_SECONDS + duration))
        
        # Add to total moved size
        unit=$(echo "$size" | grep -o "[A-Z]")
        val=$(echo "$size" | grep -o "[0-9]*")
        db=$(to_bytes "$val" "$unit")
        TOTAL_BYTES_MOVED=$(echo "$TOTAL_BYTES_MOVED + $db" | bc)
    else
        printf "${RED}${BOLD}✖ Task Failed${NC}\n" | tee -a "$LOG_DONE"
        ((FAILED_COUNT++))
    fi

done < "$DISK_LIST_FILTERED"

# --- STEP 6: Final Summary ---
HUM_MOVED=$(echo "scale=2; $TOTAL_BYTES_MOVED / 1073741824" | bc)
MINUTES=$((TOTAL_TIME_SECONDS / 60))
SECONDS=$((TOTAL_TIME_SECONDS % 60))

echo -e "\n----------------------------------------------------------------"
echo -e "${L_BLUE}${BOLD}MIGRATION SUMMARY:${NC}"
echo -e "  Storages:      ${YELLOW}$SRC_STORAGE${NC} -> ${YELLOW}$DEST_STORAGE${NC}"
echo -e "  Successful:    ${GREEN}$SUCCESS_COUNT${NC}"
echo -e "  Failed:        ${RED}$FAILED_COUNT${NC}"
echo -e "  Total Volume:  ${BOLD}$HUM_MOVED GB${NC}"
echo -e "  Total Time:    ${BOLD}$MINUTES minutes and $SECONDS seconds${NC}"
echo -e "----------------------------------------------------------------"
printf -- "${GREEN}${BOLD}✔ Process completed.${NC}\n"