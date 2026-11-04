-- ============================================================
-- Credit Card Fraud (SIMULATED data) | 04: features for the FINAL test run
-- Run from the repo root, after 01-03 (same session, or on its own: it reads the CSVs directly).
--
-- fraudTest.csv is scored once, with the model and threshold frozen on the validation slice.
-- Train and test are stacked and sorted by time within each card, so a test transaction's
-- per-card features can use that card's earlier TRAIN-period history. The windows still stop
-- one row before the current transaction, so nothing ever looks forward.
-- This file builds features only. It does not tune anything and does not query test fraud rates.
-- ============================================================

CREATE OR REPLACE VIEW all_tx AS
SELECT *, 'train' AS src FROM read_csv_auto('data/fraudTrain.csv')
UNION ALL
SELECT *, 'test'  AS src FROM read_csv_auto('data/fraudTest.csv');

CREATE OR REPLACE VIEW feats_all AS
WITH base AS (
    SELECT src, cc_num, is_fraud, amt, category, city_pop, lat, "long", merch_lat, merch_long,
           CAST(trans_date_trans_time AS TIMESTAMP) AS ts,
           CAST(dob AS DATE) AS dob_d
    FROM all_tx
)
SELECT src, ts, cc_num, amt, is_fraud, category, city_pop,
       hour(ts) AS hr, isodow(ts) AS dow_num,
       date_diff('year', dob_d, CAST(ts AS DATE)) AS age,
       LN(amt) AS log_amt,
       2 * 6371 * asin(sqrt(
           pow(sin(radians(merch_lat - lat) / 2), 2) +
           cos(radians(lat)) * cos(radians(merch_lat)) *
           pow(sin(radians(merch_long - "long") / 2), 2))) AS dist_km,
       amt / AVG(amt) OVER w_past                  AS amt_ratio,
       date_diff('second', LAG(ts) OVER w_ord, ts) AS secs_since_last,
       COUNT(*) OVER w_24h                         AS tx_prev_24h
FROM base
WINDOW w_ord  AS (PARTITION BY cc_num ORDER BY ts),
       w_past AS (PARTITION BY cc_num ORDER BY ts
                  ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
       w_24h  AS (PARTITION BY cc_num ORDER BY ts
                  RANGE BETWEEN INTERVAL 24 HOURS PRECEDING AND INTERVAL 1 SECOND PRECEDING);

-- Check 1: adding the test period must not change any train feature
-- (past-only features cannot see the future). The two rows should match
-- (tiny floating-point differences are fine). Needs feats2 from 03.
SELECT 'feats2 (train only)' AS source, COUNT(*) AS n, ROUND(SUM(amt_ratio), 2) AS sum_amt_ratio,
       SUM(tx_prev_24h) AS sum_tx24, SUM(secs_since_last) AS sum_secs
FROM feats2
UNION ALL
SELECT 'feats_all (train rows)', COUNT(*), ROUND(SUM(amt_ratio), 2), SUM(tx_prev_24h), SUM(secs_since_last)
FROM feats_all WHERE src = 'train';

-- Check 2: file size and dates only (no labels)
SELECT src, COUNT(*) AS n_tx, MIN(ts) AS first_tx, MAX(ts) AS last_tx, COUNT(DISTINCT cc_num) AS n_cards
FROM feats_all
GROUP BY src
ORDER BY src;
