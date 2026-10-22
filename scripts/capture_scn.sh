#!/bin/bash
echo "Capturing current Oracle SCN..."
export CURRENT_SCN=$(sqlplus -s C##CDCATUSER/CDCPassword123@//localhost:1521/ORCLPDB1 <<EOF
set heading off
set feedback off
set pagesize 0
set trimspool on
SELECT CURRENT_SCN FROM V\$DATABASE;
exit;
EOF
)
export CURRENT_SCN=$(echo $CURRENT_SCN | xargs)
if [ -z "$CURRENT_SCN" ]; then
    echo "ERROR: Failed to capture SCN."
    exit 1
fi
echo "Captured SCN: $CURRENT_SCN"

