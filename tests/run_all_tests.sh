#!/bin/bash
# Wawona Comprehensive Test Suite
# Tests all protocol implementations and features

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
COMPOSITOR_BIN="$BUILD_DIR/Wawona"
MACOS_APP_BIN="$BUILD_DIR/Wawona.app/Contents/MacOS/Wawona"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0
SKIPPED=0

test_result() {
    local status=$1
    local name=$2
    shift 2
    local message="$@"
    
    case $status in
        PASS)
            echo -e "${GREEN}✓ PASS${NC}: $name - $message"
            ((PASSED++))
            ;;
        FAIL)
            echo -e "${RED}✗ FAIL${NC}: $name - $message"
            ((FAILED++))
            ;;
        SKIP)
            echo -e "${YELLOW}⊘ SKIP${NC}: $name - $message"
            ((SKIPPED++))
            ;;
    esac
}

echo "=== Wawona Comprehensive Test Suite ==="
echo ""

# Test 1: Compositor binary exists
echo "Test 1: Compositor Binary"
if [ -f "$COMPOSITOR_BIN" ]; then
    test_result PASS "Compositor Binary" "Found at $COMPOSITOR_BIN"
elif [ -f "$MACOS_APP_BIN" ]; then
    COMPOSITOR_BIN="$MACOS_APP_BIN"
    test_result PASS "Compositor Binary" "Found app bundle binary at $COMPOSITOR_BIN"
else
    test_result FAIL "Compositor Binary" "Not found at $COMPOSITOR_BIN"
    exit 1
fi

# Test 2: Compositor starts
echo ""
echo "Test 2: Compositor Startup"
export WAYLAND_DISPLAY=wayland-0
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
mkdir -p "$XDG_RUNTIME_DIR"

"$COMPOSITOR_BIN" > /tmp/wawona_test_output.log 2>&1 &
COMPOSITOR_PID=$!
sleep 2

if kill -0 $COMPOSITOR_PID 2>/dev/null; then
    test_result PASS "Compositor Startup" "Started successfully (PID: $COMPOSITOR_PID)"
else
    test_result FAIL "Compositor Startup" "Failed to start"
    cat /tmp/wawona_test_output.log
    exit 1
fi

# Test 3: Wayland socket created
echo ""
echo "Test 3: Wayland Socket"
WAYLAND_SOCKET="$XDG_RUNTIME_DIR/wayland-0"
if [ -S "$WAYLAND_SOCKET" ]; then
    test_result PASS "Wayland Socket" "Created at $WAYLAND_SOCKET"
else
    test_result FAIL "Wayland Socket" "Not found at $WAYLAND_SOCKET"
    kill $COMPOSITOR_PID 2>/dev/null || true
    exit 1
fi

# Test 4: Protocol Compliance
echo ""
echo "Test 4: Protocol Compliance"
cd "$SCRIPT_DIR"
if [ -f "test_protocol_compliance" ]; then
    if timeout 5 ./test_protocol_compliance > /tmp/protocol_test.log 2>&1; then
        test_result PASS "Protocol Compliance" "All required protocols advertised"
        cat /tmp/protocol_test.log | grep -E "(PASS|FAIL|SKIP)"
    else
        test_result FAIL "Protocol Compliance" "Some protocols missing or incorrect"
        cat /tmp/protocol_test.log
    fi
else
    test_result SKIP "Protocol Compliance" "Test binary not built (run 'make -C tests')"
fi

# Test 5: Protocol Creation Logs
echo ""
echo "Test 5: Protocol Creation Verification"
REQUIRED_PROTOCOLS=(
    "GTK Shell protocol"
    "Plasma Shell protocol"
    "Qt Surface Extension protocol"
    "Qt Window Manager protocol"
)

for protocol in "${REQUIRED_PROTOCOLS[@]}"; do
    if grep -q "$protocol" /tmp/wawona_test_output.log 2>/dev/null; then
        test_result PASS "$protocol" "Created successfully"
    else
        test_result FAIL "$protocol" "Not found in logs"
    fi
done

# Cleanup
kill $COMPOSITOR_PID 2>/dev/null || true
wait $COMPOSITOR_PID 2>/dev/null || true

# Summary
echo ""
echo "=== Test Summary ==="
echo -e "${GREEN}Passed:${NC}  $PASSED"
echo -e "${RED}Failed:${NC}  $FAILED"
echo -e "${YELLOW}Skipped:${NC} $SKIPPED"
echo "Total:   $((PASSED + FAILED + SKIPPED))"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
fi
