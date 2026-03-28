#!/bin/bash
# ╔═══════════════════════════════════════════╗
# ║  ManageMe — Start All Services            ║
# ╚═══════════════════════════════════════════╝

cd "$(dirname "$0")"

# Kill any existing instances
lsof -ti:9090 | xargs kill -9 2>/dev/null
lsof -ti:9091 | xargs kill -9 2>/dev/null
lsof -ti:8080 | xargs kill -9 2>/dev/null
sleep 0.5

echo ""
echo "  🚀 Starting ManageMe..."
echo ""

# Start CORS proxy (background)
python3 cors_proxy.py &
PID1=$!
sleep 0.5

# Start Claude bridge (background)
python3 claude_bridge.py &
PID2=$!
sleep 0.5

# Start web server (background)
cd build/web && python3 -m http.server 8080 &
PID3=$!
cd ../..

sleep 1
echo ""
echo "  ✅ All services running!"
echo ""
echo "  🌐 App:          http://localhost:8080"
echo "  🔀 CORS proxy:   http://localhost:9090"
echo "  🤖 Claude bridge: http://localhost:9091"
echo ""
echo "  Press Ctrl+C to stop all services"
echo ""

# Open browser
open http://localhost:8080

# Wait and cleanup on exit
trap "kill $PID1 $PID2 $PID3 2>/dev/null; echo ''; echo '  Stopped.'; exit 0" INT TERM
wait
