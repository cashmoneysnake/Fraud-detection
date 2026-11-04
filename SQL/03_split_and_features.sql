-- ============================================================
-- Credit Card Fraud (SIMULATED data) | 03: time-based split + model features (TRAIN only)
-- Needs the `tx` view from 01 (same session). Run from the repo root.
--
-- Split (by time, never random):
--   fit   = before 2020-04-21     (model training)
--   valid = 2020-04-21 onward     (tuning: model choice and threshold)
-- Features:
--   feats  = features that use only the row itself.
--   feats2 = adds PAST-ONLY per-card features. The window frames stop one row
--            BEFORE the current transaction (1 PRECEDING), so a transaction never
--            sees itself or any later transaction on the same card.
-- No feature uses is_fraud. cc_num is only a grouping key, never a model input.
-- ============================================================

-- Split check: both parts need enough fraud
SELECT CASE WHEN ts < TIMESTAMP '2020-04-21' THEN 'fit' ELSE 'valid' END AS part,
       COUNT(*)                        AS n_tx,
       SUM(is_fraud)                   AS n_fraud,
       ROUND(100.0 * AVG(is_fraud), 3) AS fraud_rate_pct,
       MIN(ts)                         AS first_tx,
       MAX(ts)                         AS last_tx
FROM tx
GROUP BY part
ORDER BY part;

-- Row-only features (+ the split label)
CREATE OR REPLACE VIEW feats AS
SELECT
    ts, cc_num, amt, is_fraud,
    CASE WHEN ts < TIMESTAMP '2020-04-21' THEN 'fit' ELSE 'valid' END AS part,
    hr, isodow(ts) AS dow_num, age, LN(amt) AS log_amt, category, city_pop,
    -- distance (km) from cardholder home to merchant (haversine formula)
    2 * 6371 * asin(sqrt(
        pow(sin(radians(merch_lat - lat) / 2), 2) +
        cos(radians(lat)) * cos(radians(merch_lat)) *
        pow(sin(radians(merch_long - "long") / 2), 2)
    )) AS dist_km
FROM tx;

-- Sanity check: no null distances, sensible ranges
SELECT part, is_fraud, COUNT(*) AS n,
       ROUND(AVG(dist_km), 1)      AS avg_km,
       ROUND(MAX(dist_km), 0)      AS max_km,
       ROUND(AVG(log_amt), 2)      AS avg_log_amt,
       SUM((dist_km IS NULL)::INT) AS null_dist
FROM feats
GROUP BY part, is_fraud
ORDER BY part, is_fraud;

-- Past-only per-card features
CREATE OR REPLACE VIEW feats2 AS
SELECT *,
    AVG(amt) OVER w_past                         AS prev_avg_amt,      -- card's average amount so far
    amt / AVG(amt) OVER w_past                   AS amt_ratio,         -- this amount vs. the card's usual
    date_diff('second', LAG(ts) OVER w_ord, ts)  AS secs_since_last,   -- time since the card's last tx
    COUNT(*) OVER w_24h                          AS tx_prev_24h        -- card's tx in the previous 24 hours
FROM feats
WINDOW w_ord  AS (PARTITION BY cc_num ORDER BY ts),
       w_past AS (PARTITION BY cc_num ORDER BY ts
                  ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
       w_24h  AS (PARTITION BY cc_num ORDER BY ts
                  RANGE BETWEEN INTERVAL 24 HOURS PRECEDING AND INTERVAL 1 SECOND PRECEDING);

-- Sanity + leakage check on the fit part.
-- no_history_rows should equal the number of distinct cards in fit (one first transaction each).
SELECT is_fraud,
       COUNT(*)                                  AS n,
       ROUND(MEDIAN(amt_ratio), 2)               AS med_amt_ratio,
       ROUND(MEDIAN(secs_since_last) / 3600, 1)  AS med_hrs_since_last,
       ROUND(AVG(tx_prev_24h), 2)                AS avg_tx_prev_24h,
       SUM((prev_avg_amt IS NULL)::INT)          AS no_history_rows
FROM feats2
WHERE part = 'fit'
GROUP BY is_fraud
ORDER BY is_fraud;

SELECT COUNT(DISTINCT cc_num) AS cards_in_fit FROM feats2 WHERE part = 'fit';
