#!/usr/bin/env bash
# Copyright (c) angelizer369
# Author: angelizer369
# License: MIT
# https://github.com/angelizer369/knowledge_base/blob/main/LICENSE 

# Description:
# Migrates disks of virtual machines and containers from one Proxmox storage to another

# =================================================================
# Proxmox Migrate Disks to Storage
# =================================================================

# Color Definitions
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
L_BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

# 0. Start
printf -- "%b" "${L_BLUE}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}\n"
printf -- "%b" "${L_BLUE}${BOLD}║             PROXMOX MIGRATE DISKS TO STORAGE              ║${NC}\n"
printf -- "%b" "${L_BLUE}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}\n\n"


# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
L_BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Configuration ---
LOG_DONE="$HOME/proxmox-migrate-storage.log"
LOG_ERR="$HOME/proxmox-migrate-storage-err.log"
DISK_LIST_RAW="/dev/shm/disklist_raw"
DISK_LIST_FILTERED="/dev/shm/disklist_filtered"

failexit() {
    printf -- "%b" "${RED}${BOLD}!!! ERROR: $2 (Code: $1) !!!${NC}\n" | tee -a "$LOG_ERR"
    exit "$1"
}

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

rm -f "$DISK_LIST_RAW" "$DISK_LIST_FILTERED"

echo -e "${L_BLUE}${BOLD}=== Proxmox Cluster-Wide Migration Tool ===${NC}"

# --- STEP 1: Storage Selection ---
printf -- "%b" "${L_BLUE}▶ Step 1: Selecting Storages...${NC}\n"
mapfile -t storages < <(pvesm status | awk 'NR>1 {print $1}')

# Anzeige beginnt nun bei 1
for i in "${!storages[@]}"; do
    printf "  [${YELLOW}%d${NC}] %s\n" "$((i + 1))" "${storages[$i]}"
done

read -p "Select SOURCE Index: " src_idx_input
# Internen Index berechnen (Eingabe - 1)
SRC_STORAGE=${storages[$((src_idx_input - 1))]}

read -p "Select DESTINATION Index: " dest_idx_input
# Internen Index berechnen (Eingabe - 1)
DEST_STORAGE=${storages[$((dest_idx_input - 1))]}

[[ -z "$SRC_STORAGE" || -z "$DEST_STORAGE" ]] && failexit 1 "Invalid selection."
[[ "$SRC_STORAGE" == "$DEST_STORAGE" ]] && failexit 2 "Source and Destination are the same."

# --- STEP 2: Cluster-Wide Scan ---
printf -- "\n%b" "${L_BLUE}▶ Step 2: Fetching Guests & Scanning for '$SRC_STORAGE'...${NC}\n"
GUEST_DATA_RAW=$(pvesh get /cluster/resources --type vm --output-format json)

printf "${BOLD}%5s   %-10s %-6s %8s   %-10s %-25s %-10s %8s${NC}\n" "IDX" "NODE" "TYPE" "VMID" "STATUS" "NAME" "DISK" "SIZE"
echo "----------------------------------------------------------------------------------------------------"

global_idx=0

while read -r line; do
    vmid=$(echo "$line" | grep -o '"vmid":[0-9]*' | cut -d: -f2)
    node=$(echo "$line" | grep -o '"node":"[^"]*"' | cut -d'"' -f4)
    status=$(echo "$line" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
    name=$(echo "$line" | grep -o '"name":"[^"]*"' | cut -d'"' -f4)
    type_raw=$(echo "$line" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)

    if [[ "$type_raw" == "qemu" ]]; then
        type="qm"; conf_file="/etc/pve/nodes/$node/qemu-server/$vmid.conf"
    elif [[ "$type_raw" == "lxc" ]]; then
        type="pct"; conf_file="/etc/pve/nodes/$node/lxc/$vmid.conf"
    else continue; fi

    if [[ -f "$conf_file" ]] && grep -q "$SRC_STORAGE:" "$conf_file"; then
        d_status="$status"
        [[ "$status" == "running" ]] && d_status="${GREEN}running${NC}"
        [[ "$status" == "stopped" ]] && d_status="${RED}stopped${NC}"
        
        disk_lines=$(grep "$SRC_STORAGE:" "$conf_file" | grep -v "unused")
        
        while read -r dline; do
            [[ -z "$dline" ]] && continue
            disk=$(echo "$dline" | cut -d: -f1)
            size_str=$(echo "$dline" | grep -o "size=[0-9]*[G|M|K|T]*" | cut -d= -f2)
            [[ -z "$size_str" ]] && continue

            ((global_idx++))
            printf "[${YELLOW}%3d${NC}]  %-10s %-6s ${YELLOW}%8s${NC}   %-19b %-25s %-10s %8s\n" \
                "$global_idx" "$node" "[$type]" "$vmid" "$d_status" "${name:0:24}" "$disk" "$size_str"
            
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
read -p "Selection [1-4]: " filter_sel

selected_ids=""
[[ "$filter_sel" == "4" ]] && read -p "Enter Disk IDs (space separated): " selected_ids

echo -e "\nProcessing Mode:"
echo -e "  [${YELLOW}1${NC}] Bulk (Auto-confirm)"
echo -e "  [${YELLOW}2${NC}] Interactive (Confirm each)"
read -p "Selection [1-2]: " mode_sel

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

DEST_FREE_KB=$(pvesm status -storage "$DEST_STORAGE" | awk 'NR>1 {print $6}')
DEST_FREE_BYTES=$(echo "$DEST_FREE_KB * 1024" | bc)
HUM_REQ=$(echo "scale=2; $TOTAL_REQ_BYTES / 1073741824" | bc)
HUM_FREE=$(echo "scale=2; $DEST_FREE_BYTES / 1073741824" | bc)

printf "  Required: ${BOLD}%s GB${NC} | Available: ${BOLD}%s GB${NC}\n" "$HUM_REQ" "$HUM_FREE"
(( $(echo "$TOTAL_REQ_BYTES > $DEST_FREE_BYTES" | bc -l) )) && failexit 5 "Insufficient space!"

# --- STEP 5: Execution ---
printf -- "\n%b" "${L_BLUE}▶ Step 5: Migration Execution...${NC}\n"
total_count=$(wc -l < "$DISK_LIST_FILTERED")
current=0

while read -r idx node type vmid disk size status; do
    ((current++))
    
    if [[ "$mode_sel" == "2" ]]; then
        printf "${YELLOW}Confirm:${NC} Move [#%s] %s (%s) on Node '%s'? [Y/n]: " "$idx" "$disk" "$size" "$node"
        read -r ans < /dev/tty
        ans=$(echo "$ans" | tr '[:upper:]' '[:lower:]')
        [[ -n "$ans" && "$ans" != "y" ]] && { printf "${YELLOW}⏭ Skipped${NC}\n"; continue; }
    fi

    echo "----------------------------------------------------------------"
    printf "Task %d/%d: [%s] Moving %s %s [%s]...\n" "$current" "$total_count" "$node" "$type" "$vmid" "$disk"

    if [[ "$type" == "qm" ]]; then
        pvesh create /nodes/"$node"/qemu/"$vmid"/move_disk --disk "$disk" --storage "$DEST_STORAGE" --delete 1
    else
        pvesh create /nodes/"$node"/lxc/"$vmid"/move_volume --volume "$disk" --storage "$DEST_STORAGE" --delete 1
    fi

    if [ $? -eq 0 ]; then
        printf "${GREEN}${BOLD}✔ Task Finished${NC}\n" | tee -a "$LOG_DONE"
    else
        printf "${RED}${BOLD}✖ Task Failed${NC}\n" | tee -a "$LOG_DONE"
    fi

done < "$DISK_LIST_FILTERED"

echo "----------------------------------------------------------------"
printf -- "${GREEN}${BOLD}✔ Process completed.${NC}\n"