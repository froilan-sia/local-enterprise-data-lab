#!/bin/bash
echo "=========================================================="
echo "🛑 ENTERPRISE DATA LAB TEARDOWN OPTIONS"
echo "=========================================================="
echo "1) Graceful Stop (Preserves database data volumes)"
echo "2) Nuclear Wipe   (Deletes everything and reclaims disk space)"
read -rp "Select clean mode [1-2]: " choice

case $choice in
    1)
        echo "⏳ Stopping all lab containers gracefully..."
        # Stop compose stack components
        docker-compose -f docker-compose-cdc.yml down
        # Stop core database nodes (Part 5, Section 7)
        docker stop oracle19c oceanbase-ce
        docker rm oracle19c oceanbase-ce
        echo "✅ Lab paused successfully. Data remains safe inside local mount directories."
        ;;
    2)
        read -rp "⚠️ WARNING: This completely wipes out all test databases. Proceed? (y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo "☢️ Performing full cleanup routine..."
            docker-compose -f docker-compose-cdc.yml down -v
            docker stop oracle19c oceanbase-ce 2>/dev/null || true
            docker rm -v oracle19c oceanbase-ce 2>/dev/null || true
            docker network rm data-lab-net 2>/dev/null || true
            
            echo "🗑️ Clearing local directories..."
            sudo rm -rf ~/opt/oracle/oradata
            sudo rm -rf ~/oceanbase/ob_data
            sudo rm -rf ~/oceanbase/oms_data
            
            echo "✅ All disk space reclaimed successfully."
        else
            echo "Teardown aborted."
        fi
        ;;
    *)
        echo "❌ Invalid configuration choice. Exiting script."
        ;;
esac

