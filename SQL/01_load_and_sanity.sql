-- ============================================================
-- Credit Card Fraud (SIMULATED data) | 01: load + sanity check
-- DuckDB dialect. Run from the repo root, files 01 -> 04 in order, in ONE session:
--     duckdb fraud.duckdb
--     .read SQL/01_load_and_sanity.sql
-- Data: data/fraudTrain.csv (Kaggle "Credit Card Transactions Fraud Detection",
--       simulated with the Sparkov generator). Download it into data/ first.
-- Rule: all exploration and tuning uses TRAIN only. fraudTest.csv is only touched in 04.
-- ============================================================

-- Helper view with derived columns (hour, weekday, age at transaction)
CREATE OR REPLACE VIEW tx AS
SELECT
    *,
    CAST(trans_date_trans_time AS TIMESTAMP)                          AS ts,
    hour(CAST(trans_date_trans_time AS TIMESTAMP))                    AS hr,
    dayname(CAST(trans_date_trans_time AS TIMESTAMP))                 AS dow,
    date_diff('year', CAST(dob AS DATE),
              CAST(trans_date_trans_time AS DATE))                    AS age
FROM read_csv_auto('data/fraudTrain.csv');

-- Sanity check: rows, fraud count, fraud rate, date range, cards
SELECT
    COUNT(*)                         AS n_tx,
    SUM(is_fraud)                    AS n_fraud,
    ROUND(100.0 * AVG(is_fraud), 3)  AS fraud_rate_pct,
    MIN(trans_date_trans_time)       AS first_tx,
    MAX(trans_date_trans_time)       AS last_tx,
    COUNT(DISTINCT cc_num)           AS n_cards
FROM read_csv_auto('data/fraudTrain.csv');
