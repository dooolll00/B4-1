#!/bin/bash

# Agent Application System Monitor
set -u

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
CPU=$(LC_ALL=C top -bn2 -d 0.2 | grep 'Cpu(s)' | tail -n 1 | awk '{print 100 - $8}')
CPU=$(printf "%.1f" "$CPU")

# 5. Memory usage
MEM=$(free | awk '/Mem:/ {printf "%.1f", ($2-$7)/$2*100}')

# 6. Root disk usage
DISK=$(df -P / | awk 'NR==2 {gsub("%","",$5); print $5}')

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
    SIZE=$(stat -c %s "$LOG_FILE")
    ENTRY_SIZE=$(printf '%s\n' "$LOG_ENTRY" | wc -c)

    if [ $((SIZE + ENTRY_SIZE)) -gt "$MAX_SIZE" ]; then
        rm -f "$LOG_FILE.$((MAX_FILES - 1))"

        for ((i=MAX_FILES-2; i>=1; i--)); do
            if [ -f "$LOG_FILE.$i" ]; then
                mv "$LOG_FILE.$i" "$LOG_FILE.$((i+1))"
            fi
        done

        mv "$LOG_FILE" "$LOG_FILE.1"
    fi
fi

# 11. Append monitoring log
printf '%s\n' "$LOG_ENTRY" >> "$LOG_FILE"

echo
echo "[INFO] Log appended: $LOG_FILE"
echo "====== MONITOR COMPLETE ======"
