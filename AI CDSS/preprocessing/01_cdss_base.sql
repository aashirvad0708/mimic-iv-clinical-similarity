-- preprocessing/01_cdss_base.sql
-- CDSS Base Table with Tier1/Tier2 OMR assignment
-- Fixed: Blood Pressure regex for decimal values
-- Database: ../mimic.db (parent directory)

-- ============================================
-- STEP 1: Join patients + admissions
-- ============================================
CREATE OR REPLACE TABLE cdss_base_cohort AS
SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_year_group,
    a.marital_status,
    a.race,
    a.hospital_expire_flag AS mortality
FROM patients p
INNER JOIN admissions a ON p.subject_id = a.subject_id
WHERE p.anchor_age >= 18
  AND a.dischtime IS NOT NULL
  AND a.admittime < a.dischtime;

-- ============================================
-- STEP 2: TIER 1 - Admission-specific OMR
-- ============================================
CREATE OR REPLACE TABLE omr_tier1_ranked AS
SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    o.chartdate,
    o.seq_num,
    o.result_name,
    o.result_value,
    ROW_NUMBER() OVER (
        PARTITION BY c.hadm_id, o.result_name
        ORDER BY o.chartdate DESC, o.seq_num ASC
    ) AS rn
FROM cdss_base_cohort c
LEFT JOIN omr o 
  ON c.subject_id = o.subject_id
  AND o.result_name IN ('Height (Inches)', 'Weight (Lbs)', 'BMI (kg/m2)', 'Blood Pressure')
  AND o.chartdate >= CAST(c.admittime AS DATE)
  AND o.chartdate <= CAST(c.dischtime AS DATE);

CREATE OR REPLACE TABLE omr_tier1 AS
SELECT
    subject_id,
    hadm_id,
    result_name,
    result_value,
    'TIER1' AS source
FROM omr_tier1_ranked
WHERE rn = 1 AND result_value IS NOT NULL;

CREATE OR REPLACE TABLE omr_tier1_pivot AS
SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN result_name = 'Height (Inches)' THEN TRY_CAST(result_value AS DOUBLE) ELSE NULL END) AS height_inches,
    MAX(CASE WHEN result_name = 'Height (Inches)' AND result_value IS NOT NULL THEN 'TIER1' ELSE NULL END) AS height_source,
    MAX(CASE WHEN result_name = 'Weight (Lbs)' THEN TRY_CAST(result_value AS DOUBLE) ELSE NULL END) AS weight_lbs,
    MAX(CASE WHEN result_name = 'Weight (Lbs)' AND result_value IS NOT NULL THEN 'TIER1' ELSE NULL END) AS weight_source,
    MAX(CASE WHEN result_name = 'BMI (kg/m2)' THEN TRY_CAST(result_value AS DOUBLE) ELSE NULL END) AS bmi,
    MAX(CASE WHEN result_name = 'BMI (kg/m2)' AND result_value IS NOT NULL THEN 'TIER1' ELSE NULL END) AS bmi_source,
    MAX(CASE WHEN result_name = 'Blood Pressure' THEN result_value ELSE NULL END) AS blood_pressure,
    MAX(CASE WHEN result_name = 'Blood Pressure' AND result_value IS NOT NULL THEN 'TIER1' ELSE NULL END) AS bp_source
FROM omr_tier1
GROUP BY subject_id, hadm_id;

-- Parse Blood Pressure with decimal-handling regex
CREATE OR REPLACE TABLE omr_tier1_with_bp_split AS
SELECT
    subject_id,
    hadm_id,
    height_inches,
    height_source,
    weight_lbs,
    weight_source,
    bmi,
    bmi_source,
    blood_pressure,
    bp_source,
    TRY_CAST(REGEXP_EXTRACT(blood_pressure, '([0-9]*\.?[0-9]+)', 1) AS DOUBLE) AS systolic_bp_tier1,
    TRY_CAST(REGEXP_EXTRACT(blood_pressure, '/\s*([0-9]*\.?[0-9]+)', 1) AS DOUBLE) AS diastolic_bp_tier1
FROM omr_tier1_pivot;

-- ============================================
-- STEP 3: TIER 2 - Subject-level defaults
-- Fallback logic: BEFORE → AFTER → overall latest
-- ============================================
CREATE OR REPLACE TABLE omr_tier2_ranked AS
SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    o.chartdate,
    o.seq_num,
    o.result_name,
    o.result_value,
    ROW_NUMBER() OVER (
        PARTITION BY c.hadm_id, o.result_name
        ORDER BY 
            CASE 
                WHEN o.chartdate < CAST(c.admittime AS DATE) THEN 1
                ELSE 2
            END,
            o.chartdate DESC,
            o.seq_num ASC
    ) AS rn
FROM cdss_base_cohort c
LEFT JOIN omr o
  ON c.subject_id = o.subject_id
  AND o.result_name IN ('Height (Inches)', 'Weight (Lbs)', 'BMI (kg/m2)', 'Blood Pressure')
WHERE NOT EXISTS (
    SELECT 1
    FROM omr_tier1_pivot t1
    WHERE t1.hadm_id = c.hadm_id
    AND CASE o.result_name
        WHEN 'Height (Inches)' THEN t1.height_source = 'TIER1'
        WHEN 'Weight (Lbs)' THEN t1.weight_source = 'TIER1'
        WHEN 'BMI (kg/m2)' THEN t1.bmi_source = 'TIER1'
        WHEN 'Blood Pressure' THEN t1.bp_source = 'TIER1'
        ELSE FALSE
    END
);

CREATE OR REPLACE TABLE omr_tier2 AS
SELECT
    subject_id,
    hadm_id,
    result_name,
    result_value,
    'TIER2' AS source
FROM omr_tier2_ranked
WHERE rn = 1 AND result_value IS NOT NULL;

CREATE OR REPLACE TABLE omr_tier2_pivot AS
SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN result_name = 'Height (Inches)' THEN TRY_CAST(result_value AS DOUBLE) ELSE NULL END) AS height_inches,
    MAX(CASE WHEN result_name = 'Height (Inches)' AND result_value IS NOT NULL THEN 'TIER2' ELSE NULL END) AS height_source,
    MAX(CASE WHEN result_name = 'Weight (Lbs)' THEN TRY_CAST(result_value AS DOUBLE) ELSE NULL END) AS weight_lbs,
    MAX(CASE WHEN result_name = 'Weight (Lbs)' AND result_value IS NOT NULL THEN 'TIER2' ELSE NULL END) AS weight_source,
    MAX(CASE WHEN result_name = 'BMI (kg/m2)' THEN TRY_CAST(result_value AS DOUBLE) ELSE NULL END) AS bmi,
    MAX(CASE WHEN result_name = 'BMI (kg/m2)' AND result_value IS NOT NULL THEN 'TIER2' ELSE NULL END) AS bmi_source,
    MAX(CASE WHEN result_name = 'Blood Pressure' THEN result_value ELSE NULL END) AS blood_pressure,
    MAX(CASE WHEN result_name = 'Blood Pressure' AND result_value IS NOT NULL THEN 'TIER2' ELSE NULL END) AS bp_source
FROM omr_tier2
GROUP BY subject_id, hadm_id;

-- Parse Blood Pressure with decimal-handling regex
CREATE OR REPLACE TABLE omr_tier2_with_bp_split AS
SELECT
    subject_id,
    hadm_id,
    height_inches,
    height_source,
    weight_lbs,
    weight_source,
    bmi,
    bmi_source,
    blood_pressure,
    bp_source,
    TRY_CAST(REGEXP_EXTRACT(blood_pressure, '([0-9]*\.?[0-9]+)', 1) AS DOUBLE) AS systolic_bp_tier2,
    TRY_CAST(REGEXP_EXTRACT(blood_pressure, '/\s*([0-9]*\.?[0-9]+)', 1) AS DOUBLE) AS diastolic_bp_tier2
FROM omr_tier2_pivot;

-- ============================================
-- STEP 4: Merge TIER1 + TIER2
-- ============================================
CREATE OR REPLACE TABLE omr_merged AS
SELECT
    c.subject_id,
    c.hadm_id,
    COALESCE(t1.height_inches, t2.height_inches) AS height_inches,
    COALESCE(t1.height_source, t2.height_source) AS height_source,
    COALESCE(t1.weight_lbs, t2.weight_lbs) AS weight_lbs,
    COALESCE(t1.weight_source, t2.weight_source) AS weight_source,
    COALESCE(t1.bmi, t2.bmi) AS bmi,
    COALESCE(t1.bmi_source, t2.bmi_source) AS bmi_source,
    COALESCE(t1.systolic_bp_tier1, t2.systolic_bp_tier2) AS systolic_bp,
    COALESCE(t1.bp_source, t2.bp_source) AS systolic_source,
    COALESCE(t1.diastolic_bp_tier1, t2.diastolic_bp_tier2) AS diastolic_bp,
    COALESCE(t1.bp_source, t2.bp_source) AS diastolic_source
FROM cdss_base_cohort c
LEFT JOIN omr_tier1_with_bp_split t1 ON c.hadm_id = t1.hadm_id
LEFT JOIN omr_tier2_with_bp_split t2 ON c.hadm_id = t2.hadm_id;

-- ============================================
-- STEP 5: Final cdss_base
-- ============================================
CREATE OR REPLACE TABLE cdss_base AS
SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.admission_type,
    c.admission_location,
    c.discharge_location,
    c.gender,
    c.anchor_age,
    c.anchor_year,
    c.anchor_year_group,
    c.marital_status,
    c.race,
    DATEDIFF('day', c.admittime, c.dischtime) AS los_days,
    c.mortality,
    o.height_inches,
    o.height_source,
    o.weight_lbs,
    o.weight_source,
    o.bmi,
    o.bmi_source,
    o.systolic_bp,
    o.systolic_source,
    o.diastolic_bp,
    o.diastolic_source
FROM cdss_base_cohort c
LEFT JOIN omr_merged o ON c.hadm_id = o.hadm_id
ORDER BY c.hadm_id;

-- ============================================
-- CLEANUP
-- ============================================
DROP TABLE IF EXISTS cdss_base_cohort;
DROP TABLE IF EXISTS omr_tier1_ranked;
DROP TABLE IF EXISTS omr_tier1;
DROP TABLE IF EXISTS omr_tier1_pivot;
DROP TABLE IF EXISTS omr_tier1_with_bp_split;
DROP TABLE IF EXISTS omr_tier2_ranked;
DROP TABLE IF EXISTS omr_tier2;
DROP TABLE IF EXISTS omr_tier2_pivot;
DROP TABLE IF EXISTS omr_tier2_with_bp_split;
DROP TABLE IF EXISTS omr_merged;