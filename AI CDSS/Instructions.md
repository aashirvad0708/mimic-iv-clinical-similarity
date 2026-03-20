# Download DuckDB

Go here: https://duckdb.org/docs/installation/

Download: duckdb_cli-windows-amd64.zip (do differently for MAC)
Step 2 — Extract the zip in "AI CDSS" folder

You'll get: duckdb.exe

# Database file in the main folder (not to be uploaded to github)

make a mimic.db file in the AI CDSS folder
Now in the **load_tables.py** correct the folder path as per your device and load the data by running the following script in command terminal (make sure you are in the "AI CDSS" folder) : python load_tables.py
then run : python -c "import duckdb; print(duckdb.connect('mimic.db').execute('SHOW TABLES').fetchall())"
Now you'll be able to see all of these tables (if not, ask ChatGPT) : "patients.csv.gz", "admissions.csv.gz", "omr.csv.gz" "diagnoses_icd.csv.gz", "d_icd_diagnoses.csv.gz", "prescriptions.csv.gz", "procedures_icd.csv.gz", "d_icd_procedures.csv.gz", "labevents.csv.gz", "d_labitems.csv.gz", "transfers.csv.gz",

# Make 01_cdss_base table for personal details/info :

make sure you're in "AI CDSS" folder in the CLI
now run : "./duckdb.exe mimic.db"
then you'll have something like : mimic D
now just run : ".read preprocessing/01_cdss_base.sql"
now you have **cdss_base** table in mimic.db
You'll get exact detailed info of what **base personal info** you'll be working with

# Make 01_cdss_diagnoses in the database

correct the paths in **01_cdss_diagnoses.py** file as per your device
make sure you are in the "AI CDSS/preprocessing" folder in the CLI
now run "python 01_cdss_diagnoses.py"
now you have **cdss_diagnoses** table in mimic.db

# Make 01_cdss_treatment in the databse

make sure you're in "AI CDSS" folder in the CLI
now run : "./duckdb.exe mimic.db"
then you'll have something like : mimic D
now just run : ".read preprocessing/01_cdss_treatment.sql"
now you have **cdss_treatment** table in mimic.db

# If you want preview of these tables :

go to preview_table.py and remove "#" from whatever table you want to preview
now run : python preview_table.py
output : 10-25 rows of each table with each column on your browser
