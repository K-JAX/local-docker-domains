#!/bin/bash

# HAProxy Control Script
# Simple commands to start/stop/restart our root HAProxy instance

HAPROXY_CONFIG="/opt/homebrew/etc/haproxy.cfg"
HAPROXY_BIN="/opt/homebrew/bin/haproxy"

case "$1" in
    start)
        echo "Starting HAProxy..."
        if pgrep -f "haproxy.*${HAPROXY_CONFIG}" > /dev/null; then
            echo "HAProxy is already running"
            exit 0
        fi
        
        sudo "$HAPROXY_BIN" -f "$HAPROXY_CONFIG" -D
        
        # Verify it started
        sleep 1
        if pgrep -f "haproxy.*${HAPROXY_CONFIG}" > /dev/null; then
            echo "✓ HAProxy started successfully"
            echo "  Listening on ports 80 and 443"
        else
            echo "✗ HAProxy failed to start"
            exit 1
        fi
        ;;
        
    stop)
        echo "Stopping HAProxy..."
        if ! pgrep -f "haproxy.*${HAPROXY_CONFIG}" > /dev/null; then
            echo "HAProxy is not running"
            exit 0
        fi
        
        sudo pkill -f "haproxy.*${HAPROXY_CONFIG}"
        
        # Verify it stopped
        sleep 1
        if ! pgrep -f "haproxy.*${HAPROXY_CONFIG}" > /dev/null; then
            echo "✓ HAProxy stopped successfully"
        else
            echo "✗ HAProxy failed to stop"
            exit 1
        fi
        ;;
        
    restart)
        echo "Restarting HAProxy..."
        $0 stop
        sleep 1
        $0 start
        ;;
        
    status)
        if pgrep -f "haproxy.*${HAPROXY_CONFIG}" > /dev/null; then
            echo "✓ HAProxy is running"
            echo "Processes:"
            ps aux | grep "haproxy.*${HAPROXY_CONFIG}" | grep -v grep | sed 's/^/  /'
            echo ""
            echo "Port usage:"
            lsof -i :80 -i :443 2>/dev/null | grep haproxy | sed 's/^/  /' || echo "  No ports detected (may need time to bind)"
        else
            echo "✗ HAProxy is not running"
        fi
        ;;
        
    logs)
        echo "HAProxy logs (if available):"
        echo "Note: HAProxy logs to syslog by default"
        echo "Recent system logs containing 'haproxy':"
        log show --predicate 'process == "haproxy"' --info --last 5m 2>/dev/null | tail -20 || echo "No recent logs found"
        ;;
        
    *)
        echo "HAProxy Control Script"
        echo ""
        echo "Usage: $0 {start|stop|restart|status|logs}"
        echo ""
        echo "Commands:"
        echo "  start   - Start HAProxy (requires sudo)"
        echo "  stop    - Stop HAProxy"
        echo "  restart - Stop and start HAProxy"
        echo "  status  - Show HAProxy status and processes"
        echo "  logs    - Show recent HAProxy logs"
        echo ""
        echo "Quick reference:"
        echo "  Config: $HAPROXY_CONFIG"
        echo "  Binary: $HAPROXY_BIN"
        echo ""
        exit 1
        ;;
esac
