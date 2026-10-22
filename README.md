# Local Enterprise Data Lab on macOS (Apple Silicon native)

This repository provides all the infrastructure configurations, custom scripts, and code execution structures discussed throughout the 5-part data engineering lab series.

## 🛠️ Step-by-Step Lab Replication Lifecycle

### Phase 1: Native Host Preparation
Ensure you execute prerequisites natively across host parameters without running Translation Layers:
```bash
# Tap and provision core architecture bin binaries natively
brew tap InstantClientTap/instantclient
brew install instantclient-basic instantclient-sqlplus rlwrap
```

### Phase 2: Engine Deployments & Logical Structuring
Launch base topologies and assert continuous replication safety modes via system boundaries:
```bash
# Spin up isolated container setups
docker run -d --name oracle19c --shm-size=4g -p 1521:1521 ://oracle.com
```
*Ensure you link parameters into `ARCHIVELOG` state and define dedicated `cdcatuser` runtime permissions.*

### Phase 3: Infrastructure Upstream Initialization
Run and compile internal pipelines with baked drivers:
```bash
docker-compose -f docker-compose-cdc.yml up -d --build
```
Submit Debezium state hooks into Kafka processing streams:
```bash
curl -X POST -H "Content-Type: application/json" --data @oracle-source.json http://localhost:8083/connectors
curl -X POST -H "Content-Type: application/json" --data @oceanbase-sink.json http://localhost:8083/connectors
```

### Phase 4: Migration Day Run Workflow
Execute heavy bulk updates across multi-threaded workers securely without memory throttling or pipeline pollution:
```bash
# 1. Isolate target updates
curl -X PUT http://localhost:8083/connectors/oracle-cdc-connector/pause
curl -X PUT http://localhost:8083/connectors/oceanbase-sink-connector/pause

# 2. Establish uniform snapshot data states
source scripts/capture_scn.sh
python python/migrate_full_load.py

# 3. Resume streaming structures to clear catching up lags
curl -X PUT http://localhost:8083/connectors/oracle-cdc-connector/resume
```

### 🏃‍♂️ Running the Data Lab Ecosystem

Give the automation scripts execution permissions and launch the components:
```bash
chmod +x scripts/*.sh

# Boot up full platform (Networks, DBs, and Connectors)
./scripts/start_lab.sh

# When finished running tests, safely stop or clear space:
./scripts/stop_lab.sh
```

