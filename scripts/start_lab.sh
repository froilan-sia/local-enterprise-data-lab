#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

echo "=========================================================="
echo "🚀 INITIALIZING LOCAL ENTERPRISE DATA LABTopologies"
echo "=========================================================="

# 1. Establish custom network bridge (Part 3, Page 2)
if ! docker network inspect data-lab-net >/dev/null 2>&1; then
    echo "🌐 Creating custom Docker network: data-lab-net..."
    docker network create --subnet=172.19.0.0/16 data-lab-net
else
    echo "✅ Docker network data-lab-net already exists."
fi

# 2. Provision Host Directories with correct permissions (Part 2 & Part 3)
echo "📂 Provisioning persistent host mounts..."
mkdir -p ~/opt/oracle/oradata
mkdir -p ~/oceanbase/ob_data
mkdir -p ~/oceanbase/oms_data/oms_logs ~/oceanbase/oms_data/oms_store ~/oceanbase/oms_data/oms_run
chmod -R 777 ~/opt/oracle/oradata ~/oceanbase/ob_data ~/oceanbase/oms_data

# 3. Spin up Oracle Database 19c Container (Part 2, Page 4)
echo "🛢️ Launching Oracle 19c Enterprise Edition (x86 under Rosetta emulation)..."
if [ ! "$(docker ps -q -f name=oracle19c)" ]; then
    if [ "$(docker ps -aq -f status=exited -f name=oracle19c)" ]; then
        docker rm oracle19c
    fi
    docker run -d \
        --name oracle19c \
        --network data-lab-net \
        --ip 172.19.0.2 \
        --shm-size=4g \
        --memory=8g \
        --cpus=2 \
        -p 1521:1521 \
        -p 5500:5500 \
        -e ORACLE_PWD='YourSecurePassword123!' \
        -e ORACLE_SID=ORCLCDB \
        -e ORACLE_PDB=ORCLPDB1 \
        -e ORACLE_CHARACTERSET=AL32UTF8 \
        -v ~/opt/oracle/oradata:/opt/oracle/oradata \
        ://oracle.com \
        tail -f /dev/null
fi

# 4. Spin up OceanBase CE Container (Part 3, Page 4)
echo "🐳 Launching OceanBase DB Community Edition..."
if [ ! "$(docker ps -q -f name=oceanbase-ce)" ]; then
    if [ "$(docker ps -aq -f status=exited -f name=oceanbase-ce)" ]; then
        docker rm oceanbase-ce
    fi
    docker run -d \
        --name oceanbase-ce \
        --network data-lab-net \
        --ip 172.19.0.3 \
        -p 2881:2881 -p 2882:2882 \
        -e MINI_MODE=1 \
        -e OB_DATAFILE_SIZE=10G \
        -v ~/oceanbase/ob_data:/root/ob_data \
        oceanbase/oceanbase-ce:latest
fi

# 5. Build and launch Debezium & Kafka Event Stream Stack (Part 4, Page 4-6)
echo "🏗️ Building custom Debezium Connect image & starting Kafka ecosystem..."
docker-compose -f docker-compose-cdc.yml up -d --build

echo "----------------------------------------------------------"
echo "⏳ Waiting for databases to initialize background parameters..."
echo "👉 Note: Oracle database creation via Rosetta takes 5-10 minutes on first run."
echo "----------------------------------------------------------"

# Function to monitor Oracle readiness
until docker logs oracle19c 2>&1 | grep -q "DATABASE IS READY TO USE!"; do
    echo "🕒 Waiting for Oracle database configuration instance..."
    sleep 30
done
echo "✅ Oracle 19c is completely initialized and ready."

# 6. Apply database logs configuration & user permissions (Part 2, Section 2 & 3)
echo "🔐 Granting LogMiner rights and enabling ARCHIVELOG modes inside Oracle..."
docker exec -i oracle19c sqlplus / as sysdba <<EOF
SHUTDOWN IMMEDIATE;
STARTUP MOUNT;
ALTER DATABASE ARCHIVELOG;
ALTER DATABASE OPEN;
ALTER PLUGGABLE DATABASE ALL OPEN;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA (PRIMARY KEY, UNIQUE) COLUMNS;
ALTER SYSTEM SWITCH LOGFILE;
ALTER SESSION SET CONTAINER = CDB$ROOT;
CREATE USER c##cdcatuser IDENTIFIED BY CDCPassword123 DEFAULT TABLESPACE users CONTAINER = ALL;
GRANT CREATE SESSION TO c##cdcatuser CONTAINER = ALL;
GRANT LOGMINING TO c##cdcatuser CONTAINER = ALL;
GRANT SELECT ANY TRANSACTION TO c##cdcatuser CONTAINER = ALL;
GRANT SELECT ON v_\$log TO c##cdcatuser CONTAINER = ALL;
GRANT SELECT ON v_\$logfile TO c##cdcatuser CONTAINER = ALL;
GRANT SELECT ON v_\$archived_log TO c##cdcatuser CONTAINER = ALL;
GRANT SELECT ON v_\$database TO c##cdcatuser CONTAINER = ALL;
ALTER USER c##cdcatuser QUOTA UNLIMITED ON USERS;
GRANT CREATE TABLE TO c##cdcatuser CONTAINER = ALL;
GRANT EXECUTE ON DBMS_LOGMNR TO c##cdcatuser CONTAINER=ALL;
GRANT EXECUTE ON DBMS_LOGMNR_D TO c##cdcatuser CONTAINER=ALL;
exit;
EOF

# 7. Provision MetaDB rights inside OceanBase (Part 3, Page 5)
echo "🔐 Provisioning network permissions inside OceanBase sys tenant..."
sleep 10 # Give OceanBase catalog slightly more time to register server entries
docker exec -i oceanbase-ce obclient -h127.0.0.1 -P2881 -uroot@sys <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY 'aaAA11!!';
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'aaAA11!!';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
exit;
EOF

echo "=========================================================="
echo "🚀 LAB INITIALIZATION COMPLETED SUCCESSFUL!"
echo "📈 Infrastructure stack is up and listening on local ports."
echo "=========================================================="

