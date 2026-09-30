#!/system/bin/sh
# Ilitek TDDI (ILI9881X/ILI7806S) touch & display keepalive and media watchdog for SM-M326B

# 1. Immediately wake display backlight
echo 150 > /sys/class/leds/lcd-backlight/brightness 2>/dev/null
echo 150 > /sys/devices/platform/panel/panel_drv/backlight/panel/brightness 2>/dev/null

# 2. Reload Ilitek touch firmware into IRAM
run_fw_update() {
    cat /sys/class/sec/tsp/cmd_result >/dev/null 2>&1
    cat /sys/class/sec/tsp/cmd_result_all >/dev/null 2>&1
    echo fw_update > /sys/class/sec/tsp/cmd 2>/dev/null
    sleep 2.5
    cat /sys/class/sec/tsp/cmd_result >/dev/null 2>&1
    cat /sys/class/sec/tsp/cmd_result_all >/dev/null 2>&1
    echo 1 > /sys/class/sec/tsp/enabled 2>/dev/null
}

sleep 1
run_fw_update

# 3. Main watchdog loop
while true; do
    # Clear touch cmd lock if OK
    st=$(cat /sys/class/sec/tsp/cmd_status 2>/dev/null)
    if [ "$st" = "OK" ]; then
        cat /sys/class/sec/tsp/cmd_result >/dev/null 2>&1
    fi

    # Display backlight recovery: if brightness dropped to 0, restore to 150
    b=$(cat /sys/devices/platform/panel/panel_drv/backlight/panel/brightness 2>/dev/null)
    if [ -z "$b" ] || [ "$b" -eq 0 ]; then
        echo 150 > /sys/devices/platform/panel/panel_drv/backlight/panel/brightness 2>/dev/null
        echo 150 > /sys/class/leds/lcd-backlight/brightness 2>/dev/null
    fi

    # If /data is mounted, ensure /data/media/0 always exists for MTP storage
    if mountpoint -q /data; then
        if [ ! -d /data/media/0 ]; then
            mkdir -p /data/media/0/TWRP /data/media/0/Download 2>/dev/null || true
            chown -R 1023:1023 /data/media 2>/dev/null || true
            chmod -R 0775 /data/media 2>/dev/null || true
        fi
    fi

    sleep 2
done
