#!/bin/bash

# === User-configurable Variables ===
SCAN_DURATION=15
INTERVAL=120
TARGET_BSSID="00:11:22:33:44:55"
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
AIRODUMP_OUTPUT="scan_results"
#BAND="a,b,g,n,ac,ax" # Scan BOTH 2.4 GHz and 5 GHz bands (all available channels)
BAND="bg" # Scan ONLY 2.4 GHz band (b/g/n)
#BAND="a" # Scan ONLY 5 GHz band (a/ac/ax)


# === Functions ===

auto_select_interface() {
    WIFI_IFACE=$(iw dev | grep Interface | awk '{print $2}' | head -n1)
    if [ -z "$WIFI_IFACE" ]; then
        echo "No wireless interface found! Exiting."
        exit 1
    fi
    echo "Selected interface: $WIFI_IFACE"
}

kill_interfering_processes() {
    systemctl stop NetworkManager
    systemctl stop wpa_supplicant
    systemctl stop hostapd
}

set_monitor_mode() {
    ip link set "$WIFI_IFACE" down
    iw dev "$WIFI_IFACE" set type monitor
    ip link set "$WIFI_IFACE" up
    echo "Monitor mode set on $WIFI_IFACE"
}

set_managed_mode() {
    ip link set "$WIFI_IFACE" down
    iw dev "$WIFI_IFACE" set type managed
    ip link set "$WIFI_IFACE" up
    echo "Managed mode set on $WIFI_IFACE"
}

scan_targets() {
    tmux new-session -d -s airodump_scan "timeout $SCAN_DURATION airodump-ng -w $AIRODUMP_OUTPUT --band $BAND --output-format csv $WIFI_IFACE"
    tmux attach-session -t airodump_scan
}

parse_airodump() {
    local line=$(grep -i "$TARGET_BSSID" "${AIRODUMP_OUTPUT}-01.csv" | head -n1)

    if [ -z "$line" ]; then
        echo "Target BSSID not found in scan results."
        return 1
    fi

    TARGET_CHANNEL=$(echo "$line" | awk -F',' '{print $4}' | tr -d '[:space:]')
    TARGET_SSID=$(echo "$line" | awk -F',' '{print $14}' | sed 's/^ *//;s/ *$//')

    if [ -z "$TARGET_CHANNEL" ] || [ -z "$TARGET_SSID" ]; then
        echo "Failed to parse channel or SSID."
        return 1
    fi

    echo "Found BSSID: $TARGET_BSSID on Channel: $TARGET_CHANNEL with SSID: $TARGET_SSID"
}



update_hostapd_conf() {
    local current_channel=$(grep '^channel=' "$HOSTAPD_CONF" | cut -d'=' -f2)
    local current_ssid=$(grep '^ssid=' "$HOSTAPD_CONF" | cut -d'=' -f2)

    if [ "$current_channel" = "$TARGET_CHANNEL" ] && [ "$current_ssid" = "$TARGET_SSID" ]; then
        echo "hostapd.conf already set correctly. No changes required."
        return 0
    fi

    sed -i "s/^channel=.*/channel=$TARGET_CHANNEL/" "$HOSTAPD_CONF"
    sed -i "s/^ssid=.*/ssid=$TARGET_SSID/" "$HOSTAPD_CONF"

    echo "hostapd.conf updated: SSID=$TARGET_SSID, Channel=$TARGET_CHANNEL"
}

manage_hostapd_service() {
    set_managed_mode
    sleep 1

    if systemctl is-active --quiet hostapd; then
        systemctl restart hostapd
        echo "hostapd restarted."
    else
        systemctl start hostapd
        echo "hostapd started."
    fi
}
stop_hostapd_service() {
    if systemctl is-active --quiet hostapd; then
        systemctl stop hostapd
        echo "hostapd stopped due to missing target BSSID."
    else
        echo "hostapd already stopped."
    fi
}
check_hostapd_config_needs_update() {
    local current_channel=$(grep '^channel=' "$HOSTAPD_CONF" | cut -d'=' -f2)
    local current_ssid=$(grep '^ssid=' "$HOSTAPD_CONF" | cut -d'=' -f2)

    if [ "$current_channel" = "$TARGET_CHANNEL" ] && [ "$current_ssid" = "$TARGET_SSID" ]; then
        return 1  # No changes needed
    else
        return 0  # Changes are required
    fi
}

handle_hostapd_service() {
    if parse_airodump; then
        update_hostapd_conf
        if check_hostapd_config_needs_update || ! systemctl is-active --quiet hostapd; then
            manage_hostapd_service
        else
            echo "No config changes, and hostapd already running. Skipping restart."
        fi
    else
        echo "Target BSSID missing, stopping hostapd."
        stop_hostapd_service
    fi
}


remove_csv() {
    rm -f *.csv
}


# === Main Execution Loop ===
while true; do
    remove_csv
    auto_select_interface
    kill_interfering_processes
    set_monitor_mode
    scan_targets

    handle_hostapd_service

    echo "Displaying hostapd logs for $INTERVAL seconds:"
    timeout "$INTERVAL" journalctl -fu hostapd
done

