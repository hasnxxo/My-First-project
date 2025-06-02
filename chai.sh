#!/bin/bash

# ================================
# Linux User & Group Management Script
# Provides menu-based user/group management with logging, input validation, and colored output.
# Passwords expire after 45 days for created users.
# Additional options to list users and groups are provided.
# ================================

# ---------- Color Variables ----------
RED='\033[0;31m'      # Error messages
GREEN='\033[0;32m'    # Success messages
CYAN='\033[0;36m'     # Menu headers / informational output
YELLOW='\033[1;33m'   # Prompts / menu numbering
RESET='\033[0m'       # Reset to default color

# ---------- Log File Path ----------
LOG_FILE="/var/log/user_management.log"

# ---------- Root Privilege Check ----------
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}This script must be run as root (use sudo).${RESET}"
    exit 1
fi

# ---------- Logging Function ----------
log() {
    # Append timestamped log messages to the log file for auditing purposes.
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# ---------- Create User Function ----------
create_user() {
    read -p "Enter new username: " username
    # Check if the user already exists
    if id "$username" &>/dev/null; then
        echo -e "${RED}User '$username' already exists.${RESET}"
        log "Failed to create user '$username': already exists"
        return
    fi

    # Ask for shell, default to /bin/bash if no input provided
    read -p "Enter shell [/bin/bash]: " shell
    shell=${shell:-/bin/bash}

    # Securely input password twice for confirmation
    read -s -p "Enter initial password: " password
    echo
    read -s -p "Confirm password: " password_confirm
    echo
    if [[ "$password" != "$password_confirm" ]]; then
        echo -e "${RED}Passwords do not match.${RESET}"
        log "Password mismatch while creating user '$username'"
        return
    fi

    # Create the new user with the specified shell and a home directory.
    useradd -m -s "$shell" "$username"
    if [[ $? -eq 0 ]]; then
        # Set the user's password and enforce password expiration after 45 days.
        echo "$username:$password" | chpasswd
        chage -M 45 "$username"
        echo -e "${GREEN}User '$username' created. Password expires in 45 days.${RESET}"
        log "User '$username' created with shell '$shell' and 45-day password expiry"
    else
        echo -e "${RED}Failed to create user.${RESET}"
        log "Failed to create user '$username'"
    fi
}

# ---------- Delete User Function ----------
delete_user() {
    read -p "Enter username to delete: " username
    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User '$username' does not exist.${RESET}"
        log "Failed to delete user '$username': does not exist"
        return
    fi

    read -p "Remove home directory? (y/n): " remove_home
    if [[ "$remove_home" =~ ^[Yy]$ ]]; then
        userdel -r "$username"
    else
        userdel "$username"
    fi

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}User '$username' deleted.${RESET}"
        log "User '$username' deleted"
    else
        echo -e "${RED}Failed to delete user.${RESET}"
        log "Failed to delete user '$username'"
    fi
}

# ---------- Create Group Function ----------
create_group() {
    read -p "Enter group name to create: " group
    # Check if the group already exists
    if getent group "$group" &>/dev/null; then
        echo -e "${RED}Group '$group' already exists.${RESET}"
        log "Failed to create group '$group': already exists"
        return
    fi

    groupadd "$group"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Group '$group' created.${RESET}"
        log "Group '$group' created"
    else
        echo -e "${RED}Failed to create group.${RESET}"
        log "Failed to create group '$group'"
    fi
}

# ---------- Delete Group Function ----------
delete_group() {
    read -p "Enter group name to delete: " group
    if ! getent group "$group" &>/dev/null; then
        echo -e "${RED}Group '$group' does not exist.${RESET}"
        log "Failed to delete group '$group': does not exist"
        return
    fi

    groupdel "$group"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Group '$group' deleted.${RESET}"
        log "Group '$group' deleted"
    else
        echo -e "${RED}Failed to delete group.${RESET}"
        log "Failed to delete group '$group'"
    fi
}

# ---------- Add User to Group Function ----------
add_user_to_group() {
    read -p "Enter username: " username
    read -p "Enter group to add user to: " group

    if ! id "$username" &>/dev/null; then
        echo -e "${RED}User does not exist.${RESET}"
        log "Failed to add user '$username' to group: user does not exist"
        return
    fi

    if ! getent group "$group" &>/dev/null; then
        echo -e "${RED}Group does not exist.${RESET}"
        log "Failed to add user '$username' to group '$group': group does not exist"
        return
    fi

    usermod -aG "$group" "$username"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}User '$username' added to group '$group'.${RESET}"
        log "User '$username' added to group '$group'"
    else
        echo -e "${RED}Failed to add user to group.${RESET}"
        log "Failed to add user '$username' to group '$group'"
    fi
}

# ---------- Remove User from Group Function ----------
remove_user_from_group() {
    read -p "Enter username: " username
    read -p "Enter group to remove user from: " group

    if ! id "$username" &>/dev/null || ! getent group "$group" &>/dev/null; then
        echo -e "${RED}User or group does not exist.${RESET}"
        log "Failed to remove user '$username' from group '$group': not found"
        return
    fi

    # Remove specified group from the user's current group list.
    current_groups=$(id -nG "$username" | sed "s/\b$group\b//g" | xargs)
    usermod -G "$current_groups" "$username"
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}User '$username' removed from group '$group'.${RESET}"
        log "User '$username' removed from group '$group'"
    else
        echo -e "${RED}Failed to remove user from group.${RESET}"
        log "Failed to remove user '$username' from group '$group'"
    fi
}

# ---------- List Users Function ----------
list_users() {
    echo -e "${CYAN}Listing non-system users (UID >= 1000):${RESET}"
    # Filter /etc/passwd to list users with UID >= 1000 (excluding 'nobody'). Adjust if needed.
    awk -F: '$3>=1000 && $1!="nobody" {print $1}' /etc/passwd
    log "Listed users"
}

# ---------- List Groups Function ----------
list_groups() {
    echo -e "${CYAN}Listing groups (GID >= 1000):${RESET}"
    # Filter /etc/group to list groups with GID >= 1000. Adjust filtering criteria if necessary.
    awk -F: '$3>=1000 {print $1}' /etc/group
    log "Listed groups"
}

# ---------- Menu Interface Loop ----------
while true; do
    echo -e "\n${CYAN}=== Linux User & Group Management ===${RESET}"
    echo -e "${YELLOW}1.${RESET} Create User"
    echo -e "${YELLOW}2.${RESET} Delete User"
    echo -e "${YELLOW}3.${RESET} Create Group"
    echo -e "${YELLOW}4.${RESET} Delete Group"
    echo -e "${YELLOW}5.${RESET} Add User to Group"
    echo -e "${YELLOW}6.${RESET} Remove User from Group"
    echo -e "${YELLOW}7.${RESET} List Users"
    echo -e "${YELLOW}8.${RESET} List Groups"
    echo -e "${YELLOW}9.${RESET} Exit"
    read -p "Choose an option [1-9]: " choice

    case $choice in
        1) create_user ;;
        2) delete_user ;;
        3) create_group ;;
        4) delete_group ;;
        5) add_user_to_group ;;
        6) remove_user_from_group ;;
        7) list_users ;;
        8) list_groups ;;
        9) echo -e "${CYAN}Exiting...${RESET}"; break ;;
        *) echo -e "${RED}Invalid choice. Please choose again.${RESET}" ;;
    esac
done