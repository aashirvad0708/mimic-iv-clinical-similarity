# preprocessing/run_01_cdss_base.py
import duckdb
import os
from pathlib import Path

# Get paths relative to this script
SCRIPT_DIR = Path(__file__).parent
# → C:\Users\sancy\Sanidhya_VS\mimic-iv-clinical-similarity\AI CDSS\preprocessing

ROOT_DIR = SCRIPT_DIR.parent
# → C:\Users\sancy\Sanidhya_VS\mimic-iv-clinical-similarity\AI CDSS

DB_PATH = ROOT_DIR / "mimic.db"
# → C:\Users\sancy\Sanidhya_VS\mimic-iv-clinical-similarity\AI CDSS\mimic.db

SQL_FILE = SCRIPT_DIR / "01_cdss_base.sql"
# → C:\Users\sancy\Sanidhya_VS\mimic-iv-clinical-similarity\AI CDSS\preprocessing\01_cdss_base.sql

print(f"Root directory: {ROOT_DIR}")
print(f"Database: {DB_PATH}")
print(f"SQL file: {SQL_FILE}")

if not DB_PATH.exists():
    print(f"ERROR: Database not found at {DB_PATH}")
    exit(1)

if not SQL_FILE.exists():
    print(f"ERROR: SQL file not found at {SQL_FILE}")
    exit(1)

# Connect and execute
print("\nConnecting to DuckDB...")
con = duckdb.connect(str(DB_PATH))

with open(SQL_FILE, 'r') as f:
    sql_script = f.read()

print("Executing 01_cdss_base.sql...")
con.execute(sql_script)

# Verify table was created
result = con.execute("SELECT COUNT(*) FROM cdss_base").fetchall()
row_count = result[0][0]

con.close()

print(f"✓ cdss_base table created successfully!")
print(f"✓ Total rows: {row_count:,}")
print(f"✓ Located in: {DB_PATH}")