#!/bin/bash

# Function to display the menu
show_menu() {
    clear
    echo "======================================"
    echo " Proxmox Scripts Main Menu"
    echo "======================================"
    echo "Please select a script to run:"
    
    # Find all shell scripts in the current directory, excluding this one.
    scripts=()
    i=1
    for file in *.sh; do
        if [[ "$file" != "main_menu.sh" ]]; then
            echo "$i) $file"
            scripts+=("$file")
            ((i++))
        fi
    done

    echo "0) Exit"
    echo "======================================"
}

# Main loop
while true; do
    show_menu
    read -p "Enter your choice [0-$((${#scripts[@]}))]: " choice

    # Validate input
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 0 ] || [ "$choice" -gt "${#scripts[@]}" ]; then
        echo "Invalid input. Please press Enter and try again."
        read -p ""
        continue
    fi

    # Exit condition
    if [ "$choice" -eq 0 ]; then
        echo "Exiting."
        break
    fi

    # Get selected script
    selected_script="${scripts[$((choice-1))]}"

    # Execute the selected script from GitHub
    if [[ -n "$selected_script" ]]; then
        echo "Executing $selected_script from GitHub..."
        echo "--------------------------------------"
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/angelizer369/knowledge_base/refs/heads/main/ProxmoxVE/scripts/$selected_script)"
        echo "--------------------------------------"
        echo "$selected_script finished. Press Enter to return to the menu."
        read -p ""
    else
        echo "Error: Script not found."
        echo "Press Enter to return to the menu."
        read -p ""
    fi
done
