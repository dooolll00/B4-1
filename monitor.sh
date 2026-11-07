#!/bin/bash

# Agent Application System Monitor
set -u
set -o pipefail
export LC_ALL=C

fail() {
    echo "[ERROR] $*" >&2
    exit 1
}

APP_NAME="agent-app-linux-x86"
APP_PORT=15034
LOG_DIR="/var/log/agent-app"
LOG_FILE="$LOG_DIR/monitor.log"

MAX_SIZE=$((10 * 1024 * 1024))
MAX_FILES=10

echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"

# 1. Application process health check
PID=$(pgrep -u agent-admin -f "/agent-app-linux-x86" | head -n 1)

if [ -z "$PID" ]; then
    echo "[FAIL] Application process not running"
    exit 1
fi

echo "Checking process '$APP_NAME'... [OK] (PID: $PID)"

# 2. Port health check
if ! ss -ltnH "( sport = :$APP_PORT )" | grep -q LISTEN; then
    echo "[FAIL] Port $APP_PORT is not LISTEN"
    exit 1
fi

echo "Checking port $APP_PORT... [OK]"

# 3. Firewall status
if ! sudo -n ufw status 2>/dev/null | grep -q "Status: active"; then
    echo "[WARNING] UFW firewall is inactive or status unavailable"
fi

# 4. CPU usage
CPU=$(top -bn2 -d 0.2 | awk '/Cpu\(s\)/ {
    idle = ""
    for (i = 2; i <= NF; i++) {
        if ($i == "id," || $i == "id") idle = $(i-1)
    }
} END {if (idle == "") exit 1; printf "%.1f", 100-idle}') || fail "Cannot collect CPU usage"

# 5. Memory usage
MEM=$(free | awk '/Mem:/ {if ($2 <= 0 || NF < 7) exit 1; printf "%.1f", ($2-$7)/$2*100; found=1} END {if (!found) exit 1}') || fail "Cannot collect memory usage"

# 6. Root disk usage
DISK=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}') || fail "Cannot collect disk usage"

for VALUE in "$CPU" "$MEM" "$DISK"; do
    [[ "$VALUE" =~ ^[0-9]+([.][0-9]+)?$ ]] || fail "Invalid resource measurement"
    awk -v v="$VALUE" 'BEGIN {exit !(v>=0 && v<=100)}' || fail "Resource measurement out of range"
done
[[ "$DISK" =~ ^[0-9]+$ ]] || fail "Invalid disk usage"

echo
echo "[RESOURCE MONITORING]"
echo "CPU Usage : $CPU%"
echo "MEM Usage : $MEM%"
echo "DISK Used : $DISK%"

# 7. Threshold warnings
if awk -v v="$CPU" 'BEGIN {exit !(v>20)}'; then
    echo "[WARNING] CPU threshold exceeded ($CPU% > 20%)"
fi

if awk -v v="$MEM" 'BEGIN {exit !(v>10)}'; then
    echo "[WARNING] MEM threshold exceeded ($MEM% > 10%)"
fi

if [ "$DISK" -gt 80 ]; then
    echo "[WARNING] DISK threshold exceeded ($DISK% > 80%)"
fi

# 8. Log directory check
if [ ! -d "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ]; then
    echo "[ERROR] Log directory not writable: $LOG_DIR"
    exit 1
fi

# 9. Prepare monitoring log entry
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_ENTRY="[$TIMESTAMP] PID:$PID CPU:$CPU% MEM:$MEM% DISK_USED:$DISK%"

# 10. Log rotation (10MB per file, maximum 10 files)
if [ -f "$LOG_FILE" ]; then
    SIZE=$(stat -c %s "$LOG_FILE") || fail "Cannot read log size: $LOG_FILE"
    [[ "$SIZE" =~ ^[0-9]+$ ]] || fail "Invalid log size: $LOG_FILE"
    ENTRY_SIZE=$(printf '%s\n' "$LOG_ENTRY" | wc -c)

    if [ $((SIZE + ENTRY_SIZE)) -gt "$MAX_SIZE" ]; then
        rm -f "$LOG_FILE.$((MAX_FILES - 1))" || fail "Cannot remove oldest log"

        for ((i=MAX_FILES-2; i>=1; i--)); do
            if [ -f "$LOG_FILE.$i" ]; then
                mv "$LOG_FILE.$i" "$LOG_FILE.$((i+1))" || fail "Cannot rotate log: $LOG_FILE.$i"
            fi
        done

        mv "$LOG_FILE" "$LOG_FILE.1" || fail "Cannot rotate current log"
    fi
fi

# 11. Append monitoring log
printf '%s\n' "$LOG_ENTRY" >> "$LOG_FILE" || fail "Cannot append log: $LOG_FILE"

echo
echo "[INFO] Log appended: $LOG_FILE"
echo "====== MONITOR COMPLETE ======"
