import os
import oracledb
import pymysql
from concurrent.futures import ProcessPoolExecutor, as_completed

# -------- CONFIGURATION --------
ORACLE_DSN = "localhost:1521/ORCLPDB1"
ORACLE_USER = "C##CDCATUSER"
ORACLE_PWD = "CDCPassword123"

OCEANBASE_HOST = "localhost"
OCEANBASE_PORT = 2881
OCEANBASE_USER = "root@sys"
OCEANBASE_PWD = "aaAA11!!"
OCEANBASE_DB = "test_db"

SOURCE_TABLE = "C__CDCATUSER.LARGE_ORDERS_TABLE"
TARGET_TABLE = "orders"
CHUNK_SIZE = 1000  # Batch size for bulk inserts

# Read the consistent SCN set by capture_scn.sh
CURRENT_SCN = os.environ.get('CURRENT_SCN')
if not CURRENT_SCN:
    raise ValueError(
        "CURRENT_SCN environment variable not set. "
        "Please run 'source capture_scn.sh' before executing this script."
    )

# Cap workers to protect local Docker Desktop memory limits
MAX_WORKERS = min(4, os.cpu_count()) 
# ---------------------------------

def get_rowid_chunks():
    """Query Oracle to divide the data into evenly sized chunk boundaries by physical block."""
    conn = oracledb.connect(user=ORACLE_USER, password=ORACLE_PWD, dsn=ORACLE_DSN)
    cursor = conn.cursor()
    
    sql = f"""
    SELECT 
        MIN(ROWID) as start_rowid, 
        MAX(ROWID) as end_rowid, 
        COUNT(*) as cnt
    FROM {SOURCE_TABLE}
    GROUP BY DBMS_ROWID.ROWID_BLOCK_NUMBER(ROWID)
    HAVING COUNT(*) > 0
    """
    cursor.execute(sql)
    chunks = cursor.fetchall()
    conn.close()
    return chunks

def migrate_chunk(start_rowid, end_rowid, scn):
    """Worker function: Extracts rows within a ROWID range at a frozen SCN and streams to OceanBase."""
    # 1. Read from Oracle matching the historical state snapshot
    src_conn = oracledb.connect(user=ORACLE_USER, password=ORACLE_PWD, dsn=ORACLE_DSN)
    src_cursor = src_conn.cursor()
    
    sql_extract = f"""
    SELECT * FROM {SOURCE_TABLE}
    AS OF SCN {scn}
    WHERE ROWID BETWEEN :1 AND :2
    """
    src_cursor.execute(sql_extract, (start_rowid, end_rowid))
    
    # 2. Open connection to target OceanBase instances
    ob_conn = pymysql.connect(
        host=OCEANBASE_HOST,
        port=OCEANBASE_PORT,
        user=OCEANBASE_USER,
        password=OCEANBASE_PWD,
        database=OCEANBASE_DB
    )
    ob_cursor = ob_conn.cursor()
    
    # 3. Batch and load data 
    batch = []
    for row in src_cursor:
        batch.append(row)
        if len(batch) >= CHUNK_SIZE:
            placeholders = ', '.join(['%s'] * len(row))
            ob_cursor.executemany(f"INSERT INTO {TARGET_TABLE} VALUES ({placeholders})", batch)
            ob_conn.commit()
            batch.clear()
            
    # Process remaining elements
    if batch:
        placeholders = ', '.join(['%s'] * len(row))
        ob_cursor.executemany(f"INSERT INTO {TARGET_TABLE} VALUES ({placeholders})", batch)
        ob_conn.commit()
        
    src_conn.close()
    ob_conn.close()
    return f"Successfully migrated chunk: {start_rowid} -> {end_rowid}"

if __name__ == "__main__":
    print("Initializing Parallel Full-Load Migration Routine...")
    chunks = get_rowid_chunks()
    print(f"Total chunks identified: {len(chunks)}. Spawning {MAX_WORKERS} workers.")
    print(f"Using consistent SCN: {CURRENT_SCN}")
    
    with ProcessPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(migrate_chunk, start, end, CURRENT_SCN): (start, end)
            for start, end, cnt in chunks
        }
        for future in as_completed(futures):
            try:
                print(future.result())
            except Exception as e:
                print(f"Chunk process failed: {e}")

