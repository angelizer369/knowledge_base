#!/usr/bin/env bash
# Copyright (c) angelizer369
# Author: angelizer369
# License: MIT
# https://github.com/angelizer369/knowledge_base/blob/main/LICENSE 

# Description:
# A main menu to dynamically list and run all Proxmox scripts from the repository.

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
L_BLUE='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m'

# Function to fetch scripts from GitHub
fetch_scripts() {
    echo -e "${L_BLUE}▶ Fetching scripts from GitHub...${NC}"
    api_url="https://api.github.com/repos/angelizer369/knowledge_base/contents/ProxmoxVE/scripts"
    
    # Fetch the directory listing
    script_list_json=$(curl -s "$api_url")
    if [ -z "$script_list_json" ]; then
        echo -e "${RED}Error: Could not fetch script list from GitHub.${NC}"
        return 1
    fi
    
    # Use grep and cut to parse JSON, grep for .sh files, and exclude the menu script itself
    mapfile -t scripts < <(echo "$script_list_json" | grep '"name":' | cut -d'"' -f4 | grep '\.sh$' | grep -v "proxmox__scripts_main_menu.sh")
    
    if [ ${#scripts[@]} -eq 0 ]; then
        echo -e "${YELLOW}No scripts found on GitHub.${NC}"
        return 1
    fi
    return 0
}

# Function to display the menu
show_menu() {
    clear
    printf -- "%b" "${L_BLUE}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}\n"
    printf -- "%b" "${L_BLUE}${BOLD}║                 PROXMOX SCRIPTS MAIN MENU                 ║${NC}\n"
    printf -- "%b" "${L_BLUE}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}\n\n"
    echo -e "${BOLD}Please select a script to run:${NC}"
    
    i=1
    for script in "${scripts[@]}"; do
        echo -e "  [${YELLOW}$i${NC}] $script"
        ((i++))
    done

    echo -e "\n  [${YELLOW}0${NC}] Exit"
    echo "============================================================="
}

# Main script logic
scripts=()
if ! fetch_scripts; then
    # Give a moment for the user to see the error
    sleep 3
    exit 1
fi

# Main loop
while true; do
    show_menu
    read -p "$(echo -e "${YELLOW}Enter your choice [0-$(((${#scripts[@]})))]: ${NC}")" choice

    # Validate input
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt "${#scripts[@]}" ]; then
        echo -e "\n${RED}Invalid input. Please press Enter and try again.${NC}"
        read -p ""
        continue
    fi

    # Exit condition
    if [ "$choice" -eq 0 ]; then
        echo -e "\n${GREEN}Exiting.${NC}"
        break
    fi

    # Get selected script
    selected_script="${scripts[$((choice-1))]}"

    # Execute the selected script from GitHub
    if [[ -n "$selected_script" ]]; then
        echo -e "\n${GREEN}Executing $selected_script from GitHub...${NC}"
        echo "-------------------------------------------------------------"
        base_url="https://raw.githubusercontent.com/angelizer369/knowledge_base/main/ProxmoxVE/scripts"
        bash -c "$(curl -fsSL $base_url/$selected_script)"
        echo "-------------------------------------------------------------"
        echo -e "${GREEN}$selected_script finished. Press the [Enter] key to return to the main menu...${NC}"
        read -p ""
    else
        echo -e "\n${RED}Error: Script not found.${NC}"
        echo -e "${RED}Press the [Enter] key to return to the main menu...${NC}"
        read -p ""
    fi
done
