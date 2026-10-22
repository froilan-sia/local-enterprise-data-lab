import json
import time
import pymysql
import oracledb

# -------- CONFIGURATION --------
OB_HOST = "localhost"
OB_PORT = 2881
OB_USER = "root@sys"
OB_PWD = "aaAA11!!"
OB_DATABASE = "test_db"

ORA_DSN = "localhost:1521/ORCLPDB1"
ORA_USER = "C##CDCATUSER"
ORA_PWD = "CDCPassword123"
# ---------------------------------

def process_reverse_events():
    """Polls OceanBase for transactional changes and updates Oracle to preserve data parity."""
    ob_conn = pymysql.connect(
        host=OB_HOST,
        port=OB_PORT,
        user=OB_USER,
        password=OB_PWD,
        database=OB_DATABASE
    )
    ob_cursor = ob_conn.cursor()
    
    # Extract unprocessed events
    ob_cursor.execute(
        "SELECT id, table_name, operation, row_data FROM reverse_sync_queue "
        "WHERE processed = FALSE ORDER BY id ASC FOR UPDATE"
    )
    events = ob_cursor.fetchall()
    
    if not events:
        ob_conn.close()
        return

    ora_conn = oracledb.connect(user=ORA_USER, password=ORA_PWD, dsn=ORA_DSN)
    ora_cursor = ora_conn.cursor()
    
    for event_id, table_name, operation, row_data in events:
        data = json.loads(row_data)
        
        # Handle Inserts
        if operation == 'I':
            cols = ', '.join(data.keys())
            vals = ', '.join([f"'{v}'" if v is not None else "NULL" for v in data.values()])
            ora_cursor.execute(f"INSERT INTO C##CDCATUSER.{table_name.upper()} ({cols}) VALUES ({vals})")
            
        # Handle Updates
        elif operation == 'U':
            pk_val = data.get('order_id') or data.get('id')
            pk_col = 'order_id' if 'order_id' in data else 'id'
            
            set_clause = ', '.join([
                f"{k}='{v}'" if v is not None else f"{k}=NULL" 
                for k, v in data.items() if k != pk_col
            ])
            ora_cursor.execute(f"UPDATE C##CDCATUSER.{table_name.upper()} SET {set_clause} WHERE {pk_col} = '{pk_val}'")
            
        # Handle Deletes
        elif operation == 'D':
            pk_val = data.get('order_id') or data.get('id')
            pk_col = 'order_id' if 'order_id' in data else 'id'
            ora_cursor.execute(f"DELETE FROM C##CDCATUSER.{table_name.upper()} WHERE {pk_col} = '{pk_val}'")
            
        # Mark event as resolved in OceanBase MetaDB
        ob_cursor.execute("UPDATE reverse_sync_queue SET processed = TRUE WHERE id = %s", (event_id,))
        
    # Flush changes sequentially
    ob_conn.commit()
    ora_conn.commit()
    
    print(f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] Processed {len(events)} reverse sync events.")
    ob_conn.close()
    ora_conn.close()

if __name__ == "__main__":
    print("Starting Lightweight Reverse Sync Fallback Daemon...")
    print("Monitoring OceanBase mutations for safe application rollbacks...")
    
    while True:
        try:
            process_reverse_events()
            time.sleep(5)
        except KeyboardInterrupt:
            print("\nGracefully terminating sync processes.")
            break
        except Exception as e:
            print(f"Error in daemon synchronization processing chain: {e}")
            time.sleep(10)  # Cool-off period if connections fail

