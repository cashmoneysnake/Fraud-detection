-- ============================================================
-- Credit Card Fraud (SIMULATED data) | 02: where does fraud concentrate? (TRAIN only)
-- Needs the `tx` view from 01 (same session). Run from the repo root.
-- "Lift" = a segment's fraud rate divided by the overall fraud rate.
-- ============================================================

-- 1. Fraud by merchant category: rate, lift vs baseline, fraud dollars
WITH base AS (SELECT AVG(is_fraud) AS rate FROM tx)
SELECT
    category,
    COUNT(*)                                          AS n_tx,
    SUM(is_fraud)                                     AS n_fraud,
    ROUND(100.0 * AVG(is_fraud), 3)                   AS fraud_rate_pct,
    ROUND(AVG(is_fraud) / (SELECT rate FROM base), 2) AS lift_vs_base,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END), 0) AS fraud_dollars
FROM tx
GROUP BY category
ORDER BY fraud_rate_pct DESC;

-- 2. Fraud by hour of day
SELECT
    hr,
    COUNT(*)                        AS n_tx,
    SUM(is_fraud)                   AS n_fraud,
    ROUND(100.0 * AVG(is_fraud), 3) AS fraud_rate_pct
FROM tx
GROUP BY hr
ORDER BY hr;

-- 3. Fraud by cardholder age band
SELECT
    CASE WHEN age < 25 THEN '1: <25'
         WHEN age < 35 THEN '2: 25-34'
         WHEN age < 50 THEN '3: 35-49'
         WHEN age < 65 THEN '4: 50-64'
         ELSE               '5: 65+' END AS age_band,
    COUNT(*)                        AS n_tx,
    SUM(is_fraud)                   AS n_fraud,
    ROUND(100.0 * AVG(is_fraud), 3) AS fraud_rate_pct,
    ROUND(AVG(is_fraud) / (SELECT AVG(is_fraud) FROM tx), 2) AS lift_vs_base
FROM tx
GROUP BY age_band
ORDER BY age_band;

-- 4. Fraud by amount band (rate and fraud dollars)
SELECT
    CASE WHEN amt < 20   THEN '1: <$20'
         WHEN amt < 100  THEN '2: $20-99'
         WHEN amt < 300  THEN '3: $100-299'
         WHEN amt < 1000 THEN '4: $300-999'
         ELSE                 '5: $1000+' END AS amt_band,
    COUNT(*)                        AS n_tx,
    SUM(is_fraud)                   AS n_fraud,
    ROUND(100.0 * AVG(is_fraud), 3) AS fraud_rate_pct,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END), 0) AS fraud_dollars
FROM tx
GROUP BY amt_band
ORDER BY amt_band;

-- 5. Category x hour hotspots (top 10, at least 1,000 transactions per combination)
SELECT
    category,
    hr,
    COUNT(*)                        AS n_tx,
    SUM(is_fraud)                   AS n_fraud,
    ROUND(100.0 * AVG(is_fraud), 2) AS fraud_rate_pct,
    ROUND(AVG(is_fraud) / (SELECT AVG(is_fraud) FROM tx), 2) AS lift_vs_base
FROM tx
GROUP BY category, hr
HAVING COUNT(*) >= 1000
ORDER BY fraud_rate_pct DESC
LIMIT 10;

-- 6. Monthly trend (rows, fraud count, fraud dollars)
SELECT
    date_trunc('month', ts)                                   AS month,
    COUNT(*)                                                  AS n_tx,
    SUM(is_fraud)                                             AS n_fraud,
    ROUND(SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END), 0) AS fraud_dollars
FROM tx
GROUP BY month
ORDER BY month;

-- 7. Export segment tables to outputs/ (train only)
COPY (
    SELECT category, COUNT(*) AS n_tx, SUM(is_fraud) AS n_fraud,
           AVG(is_fraud) AS fraud_rate,
           SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END) AS fraud_dollars
    FROM tx GROUP BY category
) TO 'outputs/fraud_by_category.csv' (HEADER);

COPY (
    SELECT hr, COUNT(*) AS n_tx, SUM(is_fraud) AS n_fraud, AVG(is_fraud) AS fraud_rate
    FROM tx GROUP BY hr ORDER BY hr
) TO 'outputs/fraud_by_hour.csv' (HEADER);

COPY (
    SELECT date_trunc('month', ts) AS month, COUNT(*) AS n_tx, SUM(is_fraud) AS n_fraud,
           SUM(CASE WHEN is_fraud = 1 THEN amt ELSE 0 END) AS fraud_dollars
    FROM tx GROUP BY month ORDER BY month
) TO 'outputs/fraud_by_month.csv' (HEADER);
