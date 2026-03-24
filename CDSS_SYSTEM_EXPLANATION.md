# CDSS Retrieval System: Implementation Explanation

## 1. Simple Explanation First

This system is a **clinical similarity and recommendation engine** built on top of structured hospital admission data.

In simple terms, it works like this:

1. Read patient admissions from DuckDB.
2. Represent each admission using diagnoses, demographics, and later treatments.
3. Find historical admissions that look most similar to a given patient.
4. Use those similar admissions to suggest likely treatments.
5. Return both the results and an explanation of why they matched.

This is a **case-based reasoning** system:

- input: a patient profile or `hadm_id`
- process: retrieve similar past admissions
- output: similar cases + recommended treatments + explainability

It started with a **diagnosis-only baseline**, then expanded into:

- an ML validation workflow
- treatment-aware retrieval
- diagnosis+treatment hybrid retrieval
- a fast API-backed dashboard retriever

---

## 2. Overall Goal of the System

The goal is to support a **Clinical Decision Support System (CDSS)** by retrieving similar hospital admissions and using those past cases to inform decisions.

The system is designed to answer questions like:

- Which past patients are most similar to this one?
- What diagnoses or disease groups overlap?
- What treatments were commonly given to similar patients?
- What procedures were common in similar cases?
- Can we show these results quickly in a dashboard?

This is not a text search engine. It is a **structured clinical retrieval system** built over tabular hospital data.

---

## 3. High-Level Architecture

```text
Raw MIMIC tables
    |
    v
Preprocessing / feature-table creation
    |
    +--> cdss_base
    +--> cdss_diagnoses
    +--> cdss_treatment
    |
    v
Python loaders + validation
    |
    +--> diagnosis-only similarity baseline
    +--> ML validation workflow
    +--> treatment similarity layer
    +--> hybrid diagnosis+treatment retrieval
    +--> dashboard backend API
    |
    v
Outputs
    +--> CLI tables
    +--> FastAPI JSON
    +--> React dashboard
```

---

## 4. End-to-End Pipeline

```text
Input query
  |
  +--> existing hadm_id
  |      or
  +--> custom patient JSON profile
  |
  v
Normalize fields
  - convert DuckDB lists to Python lists
  - handle nulls
  - derive fallback diagnosis groups if needed
  |
  v
Candidate retrieval
  - initially: score many/all rows
  - later: DuckDB candidate pruning
  |
  v
Similarity scoring
  - diagnosis overlap
  - treatment overlap
  - demographic/context closeness
  |
  v
Rank top-K similar admissions
  |
  v
Aggregate treatments from a larger similar-patient pool
  |
  v
Return
  - similar patients
  - scores
  - prescriptions
  - procedures
  - explanations
```

---

## 5. Main Components Used

### Database

- **DuckDB**

Main tables:

- `cdss_base`
- `cdss_diagnoses`
- `cdss_treatment`

### Data handling

- **pandas**
- **numpy**

### Original ML / similarity stack

- **scikit-learn**
  - `NearestNeighbors(metric="cosine")`
  - `StandardScaler`
  - `OneHotEncoder`
  - `MultiLabelBinarizer`

### API / frontend

- **FastAPI**
- **React**
- **Vite**

### Testing

- **pytest**

### Important note

The current system does **not** use:

- embeddings
- BM25
- FAISS
- vector DBs
- transformer encoders

This is a **structured retrieval system over tabular clinical data**, not a semantic embedding search system.

---

## 6. Data Tables and Their Roles

### `cdss_base`

Used for:

- demographics
- physiology/context
- outcomes

Key fields include:

- `age`
- `gender`
- `race`
- `bmi`
- `systolic_bp`
- `diastolic_bp`
- `los_days`
- `mortality`

### `cdss_diagnoses`

Used for diagnosis-based matching.

Key fields include:

- `primary_diagnosis_icd`
- `primary_icd_3digit`
- `diagnoses_icd_list`
- `diagnoses_3digit_list`
- `diagnosis_count`
- `unique_icd_count`
- `diagnosis_diversity_ratio`
- `icd_version_mix`

### `cdss_treatment`

Used for treatment recommendation and procedure-aware retrieval.

Depending on the DB state, the system supports:

1. an already-aggregated admission-level treatment format
2. a raw/tall treatment-event format that gets aggregated on the fly

It also enriches procedures using:

- `d_icd_procedures`

---

## 7. Diagnosis-Only Baseline

The first implemented system was diagnosis-only retrieval.

### What it does

- loads `cdss_diagnoses`
- normalizes DuckDB list columns to Python lists
- validates null constraints
- checks `diagnosis_count >= unique_icd_count`
- precomputes:
  - `dx_set`
  - `dx_3_set`

### Core similarity function

It uses **Jaccard similarity** on diagnosis sets.

Formula:

```text
Jaccard(A, B) = |A ∩ B| / |A ∪ B|
```

This is used on:

- full ICD code sets
- 3-digit grouped ICD sets

### Baseline patient similarity

The diagnosis baseline combines 3 signals:

1. exact primary diagnosis match
2. Jaccard on full ICD list
3. Jaccard on 3-digit ICD groups

Formula:

```text
diag_sim =
  0.40 * primary_match
+ 0.35 * jaccard(full_icd)
+ 0.25 * jaccard(3digit_icd)
```

Where:

- `primary_match` is `1` if primary diagnoses match exactly, else `0`

### Interpretation

This is already a small hybrid design:

- exact symbolic match
- fine-grained set overlap
- coarser semantic overlap

---

## 8. ML Workflow Layer

After building the diagnosis baseline, an ML workflow was added to evaluate whether the retrieval signal is useful.

### What it does

- joins `cdss_base + cdss_diagnoses + aggregated cdss_treatment`
- performs dataset validation
- auto-detects available outcomes
- runs a Phase 1 sanity workflow
- runs a Phase 2 outcome-alignment test

### Main purpose

To answer:

- Does diagnosis similarity correlate with mortality?
- Is the retrieval baseline useful before adding more features?

### Observed result

The quick smoke test showed weak diagnosis-only mortality alignment:

```text
correlation = -0.004359
```

Meaning:

- the code worked
- diagnosis-only similarity was weak for mortality
- more clinical features were needed

That motivated the treatment layer and richer hybrid retrieval.

---

## 9. Treatment Similarity Layer

The treatment side was added as a compatibility layer for the actual database that existed.

### What it does

If `cdss_treatment` already has aggregated admission-level fields:

- load them directly

Otherwise:

- derive treatment features from:
  - `prescriptions`
  - `procedures_icd`
  - `d_icd_procedures`

### Derived treatment features include

- `rx_drug_list`
- `proc_icd_list`
- `rx_unique_drugs`
- `proc_count`
- `surgery_count`
- `treatment_days`
- `treatment_complexity_score`
- `treatment_intensity_label`

### Treatment similarity formula

```text
treatment_sim =
  0.40 * drug_jaccard
+ 0.35 * procedure_jaccard
+ 0.15 * complexity_similarity
+ 0.10 * duration_similarity
```

Where:

```text
complexity_similarity = 1 - |score_a - score_b|
duration_similarity = 1 - |days_a - days_b| / max(days_a, days_b, 1)
```

This gives a treatment-aware notion of patient similarity.

---

## 10. Hybrid Clinical Retrieval

Then diagnosis similarity and treatment similarity were combined into a more complete clinical retriever.

### Formula

```text
clinical_sim =
  0.60 * diagnosis_similarity
+ 0.40 * treatment_similarity
```

This means:

- diagnosis is still the stronger signal
- treatment overlap adds extra realism and specificity

### Why this matters

Two patients can have similar diagnoses but very different treatment intensity.

Example:

```text
Patient A: CHF + diabetes, simple meds
Patient B: CHF + diabetes, multiple procedures and IV-heavy care
```

Diagnosis-only retrieval might rank them closely.
Clinical hybrid retrieval can separate them better.

---

## 11. Original kNN CDSS Layer

Before the fast backend rewrite, a full feature-matrix approach was implemented.

### Features used

- age
- gender
- race
- bmi
- systolic BP
- diastolic BP
- diagnosis_count
- unique_icd_count
- diagnosis_diversity_ratio
- diagnosis lists
- diagnosis 3-digit groups

### Encoding strategy

- numeric features:
  - median imputation
  - `StandardScaler`
- categorical features:
  - one-hot encoding
- diagnosis lists:
  - multi-hot encoding

### Similarity model

`NearestNeighbors(metric="cosine")`

Similarity conversion:

```text
similarity = 1 - cosine_distance
```

### Why it was replaced for the dashboard

It worked, but it was too slow for a responsive frontend when used over a large MIMIC-sized dataset.

---

## 12. Procedure Recommendation Improvements

Later, the system was improved so the UI explicitly surfaces procedures.

### What changed

- procedure recommendations got their own section in the frontend
- procedure names were enriched from `d_icd_procedures`
- recommendation generation used a larger neighbor pool than the small displayed top-K

This made procedure recommendations much more likely to appear.

### Why the enrichment matters

Instead of showing only a code-like key, the system shows human-readable procedure names such as:

- `Resection of Right Lung, Percutaneous Endoscopic Approach`
- `Excision of Facial Nerve, Open Approach`

---

## 13. Fast Backend Retrieval Design

To make dashboard submit fast, the backend replaced the heavy full-dataset kNN path with a fast retrieval approach.

### New strategy

Instead of:

- loading all admissions
- building a large global feature matrix
- fitting a kNN model over everything

It now does:

1. **candidate generation in DuckDB**
2. **Python reranking on a bounded candidate set**
3. **treatment aggregation from a larger recommendation pool**

This is much more like an information retrieval pipeline.

---

## 14. How Hybrid Retrieval Is Implemented

There are actually multiple “hybrid” layers in this system.

### Hybrid type 1: diagnosis hybrid

```text
primary exact match
+ full ICD Jaccard
+ 3-digit ICD Jaccard
```

### Hybrid type 2: clinical hybrid

```text
diagnosis similarity
+ treatment similarity
```

### Hybrid type 3: backend retrieval hybrid

```text
DuckDB candidate retrieval
+ Python final reranking
```

So hybrid retrieval here means combining:

- different feature signals
- different scoring layers
- database-side ranking + application-side reranking

---

## 15. Backend Candidate Retrieval in DuckDB

The backend now uses DuckDB to retrieve a **larger but bounded candidate pool**.

The candidate pool was widened to:

```text
candidate_limit = 12000
```

by default.

It ranks candidates using database-side signals such as:

- primary diagnosis exact match
- diagnosis group overlap count
- diagnosis overlap count
- primary diagnosis group match
- age distance

### Candidate ordering idea

```text
ORDER BY
  primary_match DESC,
  dx_group_overlap_count DESC,
  dx_overlap_count DESC,
  primary_group_match DESC,
  age_distance ASC
```

This is efficient because:

- the database does the first-pass ranking
- Python only reranks a manageable subset

---

## 16. Python Reranking Logic

Once candidates are retrieved, the backend computes a final similarity score in Python.

### Final scoring formula

```text
similarity =
  0.50 * group_similarity
+ 0.25 * dx_similarity
+ 0.15 * primary_match
+ 0.10 * context_similarity
```

Where:

- `group_similarity` = Jaccard over 3-digit diagnosis groups
- `dx_similarity` = Jaccard over full ICD lists
- `primary_match` = exact match on primary diagnosis
- `context_similarity` = demographic/physiology closeness

### Context similarity

It uses:

- Gaussian closeness for:
  - age
  - BMI
  - systolic BP
  - diastolic BP
- exact equality for:
  - gender
  - race

Gaussian closeness looks like:

```text
exp(- (x - y)^2 / (2 * scale^2))
```

This means:

- similar values get a score near 1
- far values decay smoothly

---

## 17. Treatment Recommendation Scoring

After similar patients are found, the system aggregates treatments from a **larger recommendation pool**, not just the visible 5 neighbors.

This improves stability and makes procedures show up more often.

### Earlier scoring formulas

The treatment recommender uses ideas like:

```text
score = frequency * (1 / avg_los)
weighted_score = Σ(similarity / los_days)
```

Interpretation:

- treatments common among similar patients score higher
- treatments associated with lower LOS get boosted
- highly similar neighbors contribute more

### Current improvements

The backend also filters noisy treatment rows such as:

- `flush`
- `Bag`

This makes recommendations more clinically meaningful.

---

## 18. Optimizations and Design Decisions

### Data normalization

- DuckDB list columns are normalized to Python lists early.
- This avoids downstream type problems.

### Validation

- critical null checks
- diagnosis count relationship checks
- treatment feature consistency checks

### Precomputation

Set columns are precomputed where useful:

- `dx_set`
- `dx_3_set`
- `rx_set`
- `proc_set`

This avoids repeated `set(...)` conversions.

### Schema compatibility

Treatment loading supports:

- handoff-style aggregated treatment schema
- raw event-table schema

This was an important practical design decision because the live DB didn’t exactly match the documented handoff schema.

### Recommendation pool > display pool

The visible similar-patient list can be small, while treatment recommendations use more neighbors.

This improves recommendation robustness.

### Move heavy work into DuckDB

The biggest speed optimization was:

- use DuckDB to rank and narrow candidates first
- avoid full global kNN fitting at request time

---

## 19. Code Logic in Simple Terms

### `data_loader.py`

Reads diagnosis data, fixes list formats, validates columns, precomputes diagnosis sets.

### `similarity.py`

Contains diagnosis-only similarity:

- Jaccard
- weighted diagnosis similarity
- top-K similar patient retrieval

### `ml_dataset.py`

Joins core tables together into an ML-ready dataset.

### `ml_workflow.py`

Runs validation and outcome-alignment checks.

### `treatment_loader.py`

Builds admission-level treatment features, either directly or from raw tables.

### `treatment_similarity.py`

Scores treatment similarity between admissions.

### `clinical_similarity.py`

Combines diagnosis + treatment similarity and recommends treatments.

### `AI CDSS/knn_cdss.py`

Original full feature-matrix / kNN CDSS implementation.

### `project/backend/knn_cdss.py`

Fast dashboard backend retriever using DuckDB candidate selection and Python reranking.

### `project/backend/main.py`

FastAPI wrapper exposing `/health` and `/predict`.

### `project/frontend`

React dashboard that submits patient profiles and renders:

- similar patients
- prescriptions
- procedures
- explainability details

---

## 20. Example Data Flow

### Example input

```json
{
  "age": 65,
  "gender": "F",
  "race": "WHITE",
  "bmi": 26.1,
  "systolic_bp": 120,
  "diastolic_bp": 80,
  "diagnoses_icd_list": ["I10", "E119"],
  "diagnoses_3digit_list": ["10_I10", "10_E11"],
  "top_k": 5
}
```

### Flow

```text
Patient JSON
  -> normalize and validate
  -> candidate retrieval from DuckDB
  -> diagnosis/context reranking in Python
  -> top 5 similar admissions
  -> larger treatment aggregation pool
  -> group and rank prescriptions + procedures
  -> return JSON to dashboard
```

### Example live result behavior

From the implementation notes:

- response times around `1.2s` to `1.8s`
- both `prescription` and `procedure` sources returned
- top prescriptions improved after filtering
- procedures remained visible in a separate section

---

## 21. Final Output Formats

### CLI output

Examples include:

- top similar admissions
- similarity score tables
- treatment recommendation summaries

Typical fields:

- `hadm_id`
- `primary_diagnosis_icd`
- `similarity_score`

### FastAPI JSON output

Typical response shape:

```json
{
  "similar_patients": [
    {
      "hadm_id": 23942899,
      "similarity": 0.77,
      "distance": 0.23,
      "los_days": 4.0,
      "shared_diagnoses": ["I10"],
      "shared_icd_groups": ["10_I10"],
      "key_similar_features": {
        "same_gender": true,
        "same_race": true,
        "age_difference": 2.0
      }
    }
  ],
  "recommended_treatments": [
    {
      "treatment_source": "procedure",
      "treatment_name": "Resection of Right Lung, Percutaneous Endoscopic Approach",
      "frequency": 1,
      "weighted_score": 0.27
    }
  ],
  "model_info": {
    "model": "DuckDB Hybrid Retriever",
    "candidate_limit": 12000
  },
  "explanation": {
    "neighbor_count": 5,
    "recommendation_neighbor_count": 30
  }
}
```

### Frontend output

The React dashboard shows:

- similar patients table
- treatment recommendation cards
- separate procedures section
- explainability panel
- model info

---

## 22. Final Summary

### In simple terms

This project became a fast clinical case retrieval system.

It started by matching patients on diagnoses, then added treatments, then turned into a dashboard-friendly API that can:

- find similar admissions
- show why they matched
- recommend likely prescriptions
- recommend likely procedures

### In technical terms

It is a **structured hybrid retrieval system** built with:

- DuckDB for storage and first-stage candidate ranking
- pandas/numpy for feature handling
- scikit-learn for the original kNN-based similarity stack
- weighted Jaccard and hybrid clinical scoring
- LOS-aware treatment recommendation ranking
- FastAPI + React for serving and visualization

It is **not** an embedding-based or BM25-based IR system. Instead, it is a tabular, case-based, hybrid retriever over structured clinical features.

