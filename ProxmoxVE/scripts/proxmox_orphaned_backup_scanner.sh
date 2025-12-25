#!/usr/bin/env bash
# Copyright (c) angelizer369
# Author: angelizer369
# License: MIT
# https://github.com/angelizer369/knowledge_base/blob/main/LICENSE 



# =================================================================
# Proxmox Orphaned Backup Scanner
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
printf -- "%b" "${L_BLUE}${BOLD}║              PROXMOX ORPHANED BACKUP SCANNER              ║${NC}\n"
printf -- "%b" "${L_BLUE}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}\n\n"

# 1. Fetching Active Guests
printf -- "%b" "${L_BLUE}▶ Step 1: Fetching Active Guests...${NC}\n"
GUEST_DATA_RAW=$(pvesh get /cluster/resources --type vm --output-format json)

GUEST_LIST=$(echo "$GUEST_DATA_RAW" | sed 's/},{/}\n{/g' | awk -F',' '
    {
        vmid=""; name="";
        for(i=1; i<=NF; i++) {
            if($i ~ /"vmid"/) { split($i, a, ":"); vmid=a[2]; gsub(/[^0-9]/, "", vmid); }
            if($i ~ /"name"/) { split($i, b, ":"); name=b[2]; gsub(/["]/, "", name); }
        }
        if(vmid != "") print vmid " [" name "]"
    }' | sort -n)

EXISTING_IDS=$(echo "$GUEST_LIST" | awk '{print $1}' | tr '\n' ' ')

echo "$GUEST_LIST" | awk '{printf "  ├─ ID: %-8s Name: %s\n", $1, $2}'
printf "%s\n" "  └────────────────────────────────────────────────────────"

# 2. Global Variables
STORAGES=$(pvesm status | awk 'NR>1 {print $1}')
ORPHAN_COUNT=0
TOTAL_ORPHAN_SIZE=0
BREAKDOWN_LOG=""
DELETE_LIST=""

# 3. Scan Storages
printf -- "\n%b" "${L_BLUE}▶ Step 2: Scanning for ORPHANED backups...${NC}\n"

for STORAGE in $STORAGES; do
    printf "\n${BOLD}Storage:${NC} ${L_BLUE}%s${NC}\n" "$STORAGE"
    BACKUP_DATA=$(pvesm list "$STORAGE" 2>/dev/null | grep "vzdump-" || true)

    if [ -z "$BACKUP_DATA" ]; then
        printf "  ${NC}└─ No backup files detected.\n"
    else
        STORAGE_ORPHAN_FOUND=false
        STORAGE_SIZE=0
        STORAGE_COUNT=0
        while read -r LINE; do
            [ -z "$LINE" ] && continue
            VOLID=$(echo "$LINE" | awk '{print $1}')
            SIZE_BYTES=$(echo "$LINE" | awk '{for(i=1; i<=NF; i++) {if($i == "backup") {print $(i+1); break}}}')
            if [[ ! "$SIZE_BYTES" =~ ^[0-9]+$ ]]; then
                SIZE_BYTES=$(echo "$LINE" | awk '{for(i=2; i<=NF; i++) if($i ~ /^[0-9]{5,}$/) {print $i; break}}')
            fi
            VMID=$(echo "$VOLID" | sed -n 's/.*-\(qemu\|lxc\|openvz\)-\([0-9]*\)-.*/\2/p')
            [ -z "$VMID" ] && continue
            if [[ ! " $EXISTING_IDS " =~ " $VMID " ]]; then
                SIZE_GB=$(awk -v s="${SIZE_BYTES:-0}" 'BEGIN { printf "%.2f", s/1024/1024/1024 }')
                printf "  ${RED}✖${NC} ID: ${YELLOW}%-8s${NC} │ Size: ${YELLOW}%9s GB${NC} │ File: %s\n" "$VMID" "$SIZE_GB" "$VOLID"
                STORAGE_ORPHAN_FOUND=true
                ((ORPHAN_COUNT++))
                ((STORAGE_COUNT++))
                TOTAL_ORPHAN_SIZE=$(awk -v t="$TOTAL_ORPHAN_SIZE" -v n="$SIZE_GB" 'BEGIN { printf "%.2f", t+n }')
                STORAGE_SIZE=$(awk -v t="$STORAGE_SIZE" -v n="$SIZE_GB" 'BEGIN { printf "%.2f", t+n }')
                DELETE_LIST="${DELETE_LIST}${STORAGE}|${VOLID}|${VMID}|${SIZE_GB}\n"
            fi
        done <<< "$BACKUP_DATA"
        [ "$STORAGE_ORPHAN_FOUND" = true ] && BREAKDOWN_LOG="${BREAKDOWN_LOG}${STORAGE}|${STORAGE_COUNT}|${STORAGE_SIZE}\n"
        [ "$STORAGE_ORPHAN_FOUND" = false ] && printf "  ${GREEN}✔${NC} No orphaned backups found here.\n"
    fi
done

# 4. Final Summary Table
printf "\n"
printf -- "%b" "${L_BLUE}╔══════════════════════╤════════════╤══════════════════════╗${NC}\n"
printf "${L_BLUE}║${NC}                ${BOLD}FINAL RECLAMATION SUMMARY${NC}                 ${L_BLUE}║${NC}\n"
printf -- "%b" "${L_BLUE}╠══════════════════════╪════════════╪══════════════════════╣${NC}\n"
printf -- "%b" "${L_BLUE}║${NC}  ${BOLD}Storage${NC}             ${L_BLUE}│${NC}    ${BOLD}Files${NC}   ${L_BLUE}│${NC}      ${BOLD}Space (GB)${NC}      ${L_BLUE}║${NC}\n"
printf -- "%b" "${L_BLUE}╟──────────────────────┼────────────┼──────────────────────╢${NC}\n"

if [ $ORPHAN_COUNT -gt 0 ]; then
    echo -e "$BREAKDOWN_LOG" | sed '/^$/d' | while IFS='|' read -r sNAME sCOUNT sSIZE; do
        printf "${L_BLUE}║${NC} %-20s ${L_BLUE}│${NC} %10s ${L_BLUE}│${NC} %20s ${L_BLUE}║${NC}\n" "$sNAME" "$sCOUNT" "$sSIZE"
    done
    printf -- "%b" "${L_BLUE}╠══════════════════════╪════════════╪══════════════════════╣${NC}\n"
    printf "${L_BLUE}║${NC} %-20s ${L_BLUE}│${NC} ${RED}%10s${NC} ${L_BLUE}│${NC}                      ${L_BLUE}║${NC}\n" "TOTAL ORPHANED FILES" "$ORPHAN_COUNT"
    printf "${L_BLUE}║${NC} %-20s ${L_BLUE}│${NC}            ${L_BLUE}│${NC} ${RED}%20s${NC} ${L_BLUE}║${NC}\n" "TOTAL RECLAIMABLE" "$TOTAL_ORPHAN_SIZE"
else
    printf "${L_BLUE}║${NC}         ${GREEN}No orphaned backups found cluster-wide.${NC}          ${L_BLUE}║${NC}\n"
fi
printf -- "%b" "${L_BLUE}╚══════════════════════╧════════════╧══════════════════════╝${NC}\n"

# 5. Granular Cleanup Mode
if [ $ORPHAN_COUNT -gt 0 ]; then
    printf "\n%b" "${L_BLUE}▶ Step 3: Granular Cleanup Mode${NC}\n"
    printf "You will be asked for each file. Press ${BOLD}Enter${NC} for 'yes', or type ${BOLD}'n'${NC} to skip.\n"
    echo "------------------------------------------------------------"

    while IFS='|' read -r sID vID vVMID vSIZE; do
        [ -z "$sID" ] && continue
        printf "Found: ${YELLOW}%-8s${NC} (%7s GB) on ${L_BLUE}%s${NC}\n" "$vVMID" "$vSIZE" "$sID"
        printf "File:  %s\n" "$vID"

        read -p "  Delete this file? (Y/n): " confirm < /dev/tty
        confirm=${confirm:-y}

        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            printf "  ${RED}Removing...${NC} "
            [[ "$vID" == *":"* ]] && TARGET_ID="$vID" || TARGET_ID="$sID:$vID"
            if pvesm free "$TARGET_ID" >/dev/null 2>&1; then
                printf "${GREEN}DONE${NC}\n"
            else
                printf "${RED}FAILED${NC}\n"
            fi
        else
            printf "  ${L_BLUE}SKIPPED${NC}\n"
        fi
        echo "------------------------------------------------------------"
    done <<< "$(echo -e "$DELETE_LIST" | sed '/^$/d')"
    printf "\n${GREEN}${BOLD}Process finished.${NC}\n"
fi
# End of Script