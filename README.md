# Credit Card Fraud Detection & Risk Report: Which Transactions Should Get Reviewed?

> **Data disclosure:** all data is **simulated** (Sparkov generator, Kaggle "Credit Card Transactions Fraud Detection Dataset", CC0). There are no real cardholders or transactions. All dollar figures are simulated, and the savings estimate rests on my assumption of a **$5 review cost per alert**.

## Result at a glance

| | |
|---|---|
| **Fraud cases caught** | **94.4%** (2,024 of 2,145) at **40.5% precision**, PR-AUC **0.907** |
| **Fraud dollars caught** | **$1,114,753 of $1,133,325 (98.4%)** |
| **Net savings vs. no model** | **$1,089,758** (4,999 alerts, about 26 per day, at an assumed $5 per alert) |
| **Evaluation** | Time-based held-out test (2020-06-21 to 2020-12-31), scored once |
| **Dashboard** | Tableau Public: [View the dashboard]([TABLEAU PUBLIC LINK]) |

**Question:** which transactions should a fraud team review, and how many alerts is it worth sending to reviewers?

**Why it matters:** fraud is rare (0.579% of training transactions, 0.386% of test transactions), so a model that never flags anything is right on all but 0.386% of test transactions. Accuracy hides the problem. A missed fraud costs the transaction amount and a false alarm costs reviewer time, so the alert threshold is chosen by dollar cost.

**Stack:** DuckDB SQL, Python (pandas, scikit-learn, imbalanced-learn, XGBoost), Excel, Tableau Public.

## Method

| Design choice | Value |
|---|---|
| Data | Train: 1,296,675 transactions, 983 cards, 2019-01-01 to 2020-06-21. Test: 555,719 transactions, 924 cards, 2020-06-21 to 2020-12-31 |
| Split | Fit: Jan 2019 to Apr 20 2020. Validation: Apr 21 to Jun 21 2020. `fraudTest.csv` is used only for the final numbers |
| Features | log amount, merchant category, hour, day of week, age, city population, customer-to-merchant distance, and per-card features that use **past transactions only** (amount vs. the card's past average, seconds since last transaction, transactions in the prior 24 hours) |
| Left out | Identifier columns (index, transaction number, card number, names, street, raw unix time). Gender is not a model input |
| Models | Logistic regression baseline, then random forest, then XGBoost |
| Imbalance | No weighting vs. class weights vs. SMOTE, compared side by side on validation PR-AUC. SMOTE runs inside an imblearn Pipeline, so it only sees training data |
| Threshold | **0.02**, chosen on validation by net savings = fraud $ caught − $5 × alerts, before the test run |
| Review cost | $5 per alert (stated assumption) |

## Results

**Where fraud concentrates (SQL, training data only):**

- 22:00 to 03:59 holds 23.5% of transactions but about 85% of fraud.
- Transactions of $300 or more are 2.3% of transactions but about 93% of fraud dollars.
- `shopping_net` has a fraud rate of 1.756%, 3.03x the baseline.
- The riskiest segment (`misc_net` at 11 PM, at least 1,000 transactions) has a fraud rate of 26.30%, **45.43x** the baseline (314 fraud of 1,194).

**Model comparison (validation PR-AUC; random guessing = 0.0062):**

| Model | No weighting | Class weights | SMOTE |
|---|---|---|---|
| Logistic regression | 0.508 | 0.410 | 0.464 |
| Random forest | n/a | 0.873 | n/a |
| XGBoost | **0.949** | 0.943 | 0.926 |

Neither class weights nor SMOTE beat the unweighted XGBoost, so I used it and handled the imbalance with the cost-based threshold instead.

**Final test results (threshold 0.02, $5 per alert):**

| Metric | Value |
|---|---|
| PR-AUC | 0.907 |
| Precision / recall / F1 | 0.405 / 0.944 / 0.567 |
| Confusion matrix (TN / FP / FN / TP) | 550,599 / 2,975 / 121 / 2,024 |
| Fraud $ total / caught / missed | $1,133,325 / $1,114,753 (98.4%) / $18,571 |
| Review cost (4,999 alerts × $5) | $24,995 |
| **Net savings vs. no model** | **$1,089,758** |
| Break-even review cost per alert | about $223 (fraud $ caught ÷ alerts) |

On test, monthly recall ranged from 92.4% to 97.3%, and each month caught between 97.2% and 99.4% of fraud dollars. June is a partial month. The threshold choice is not fragile: on validation, net savings stayed within about 1% for thresholds from 0.005 to 0.03.

## Caveats

- **Simulated data.** Patterns are cleaner than real fraud (a sharp night/day cliff), and there are only about 1,000 customers. The numbers show the method works on this data, not what a real bank would see.
- **Net savings is an upper-bound style estimate.** It assumes every flagged fraud is actually stopped, a flat $5 review cost, and savings measured against doing nothing. The break-even of about $223 per alert shows how much that assumption matters.
- **Fraud rate drifted** from 0.579% (train) to 0.386% (test). Precision on test (0.405) is lower than on validation, partly for that reason.
- **Reruns vary slightly.** An earlier full run gave PR-AUC 0.908 and 4,934 alerts; the results here are from the committed run. Row order within identical timestamps is not fixed, which probably shifts the sampling.
- **Threshold.** I chose 0.02 on validation before the final run. In the committed run the validation best was 0.015, only 0.2% better in net savings ($501,841 vs. $500,721). I kept 0.02 because it was chosen first.
- **Model not retrained** on the final two months of training data before the test run.
- **Weak features.** Distance added almost nothing (importance 0.006). Each card's first transaction in the file looks artificially risky (63 of 971 were fraud), so those rows get a neutral fill instead of a flag.

## Repository

| File | What it is |
|---|---|
| `README.md` | This summary |
| `notebooks/01_eda.ipynb` | Full analysis: load, SQL segments, features, models, threshold, final test, exports |
| `SQL/01_load_and_sanity.sql` | Load and sanity checks |
| `SQL/02_segment_queries.sql` | Fraud rates by category, hour, age, amount, month |
| `SQL/03_split_and_features.sql` | Time-based split and past-only features |
| `SQL/04_test_features.sql` | Features for the final test run |
| `outputs/` | CSV exports behind the dashboard, charts, `final_test_summary.csv`, and `08_dollar_impact.xlsx` (results turned into dollars, with review cost as an editable input) |
| `requirements.txt` | Package versions used |

## How to reproduce

1. **Get the data.** Download the Kaggle dataset "Credit Card Transactions Fraud Detection Dataset" ([KAGGLE URL]) and put `fraudTrain.csv` and `fraudTest.csv` in a `data/` folder at the repo root. The data is not included in this repo.
2. **Set up Python** (built with 3.13.7):
   ```
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```
   On a Mac, XGBoost also needs `brew install libomp`.
3. **Run the notebook.** Open `notebooks/01_eda.ipynb` and run the cells top to bottom. The SQL runs through DuckDB inside the notebook. The files in `SQL/` hold the same queries and are meant to run from the repo root.
4. **Check your numbers.** You should see 1,296,675 training transactions with 7,506 fraud, and 555,719 test transactions with 2,145 fraud. Model results can differ from the table above by a few thousandths (see Caveats).
5. **Dashboard and Excel.** `outputs/test_by_*.csv` feed the Tableau dashboard. `outputs/08_dollar_impact.xlsx` recalculates the dollar results if you change the review cost.
