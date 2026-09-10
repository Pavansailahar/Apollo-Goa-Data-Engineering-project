# Goa Retail Sales Analytics

End-to-end retail analytics project for a Goa store network: raw Excel extracts consolidated into SQL Server, visualized in a Power BI dashboard, and explored/modeled in a Python notebook that builds a store‑SKU segmentation classifier.

> **A note on naming:** the consolidated table is referred to below as `dbo.final_sales`, which is the actual object name found in SSMS and used in the notebook's SQL query — not "Total Sales" as it's sometimes called in conversation.

---

## What's in this project

| File | Description |
|---|---|
| `Goa_final_sales.pbix` | Power BI report — dashboard + KPIs built on top of `final_sales`. |
| `Goa_data_project.ipynb` | Jupyter notebook — data pull, cleaning, EDA, anomaly detection, and a full store‑SKU segmentation pipeline (ABC/XYZ, KMeans, classifier). |
| `Goa_Sales_Project_Documentation.pdf` | Full written documentation of the schema, dashboard, and notebook (generated alongside this README). |

## Data pipeline

```
Raw Excel files (~10-15)        SQL Server                Power BI Desktop
   supplied by stakeholder  →   dbo.final_sales      →     Goa_final_sales.pbix
                                (71,76,819 rows,            (dashboard + measures)
                                 17 columns)
                                       │
                                       ▼
                                Jupyter Notebook (Python)
                                Goa_data_project.ipynb
                                pyodbc → pandas → EDA → anomaly
                                detection → feature engineering →
                                KMeans → classifier → CSV / .pkl
```

One consolidated SQL Server table feeds both the Power BI dashboard and the notebook independently — there's no dependency between the two downstream tools.

## Data source: `dbo.final_sales`

17 columns, ~71.76 lakh rows:

| Column | Type | What it holds |
|---|---|---|
| `STORE` | smallint | Store code |
| `custgroup` | int | Customer group code |
| `itemid` | nvarchar(100) | Item/SKU identifier |
| `itemname` | nvarchar(200) | Product name |
| `ctg` / `subctg` | nvarchar(100) | Category / sub-category |
| `packsize` | smallint | Pack size |
| `Generic_Flag` | nvarchar(100) | Generic vs. branded flag |
| `BILLNO` | nvarchar(100) | Bill/invoice number |
| `BILLDATETIME` | datetime2 | Full transaction timestamp |
| `BILLDATE` | date | Transaction date |
| `SALEQTY` | int | Quantity sold |
| `SALEVAL` | float | Sales value |
| `DISCOUNT` | float | Discount amount |
| `BILLS` | tinyint | Bill counter/flag (usage not confirmed — see docs) |
| `MAXSALEQTY` | int | Max recorded sale quantity for the item |
| `OFFERFLAG` | nvarchar(100) | Promotional-offer flag |

## Power BI dashboard (`Goa_final_sales.pbix`)

- **Page 1 — Main Dashboard** (1280×720): 4 KPI cards (Net Sales, Total Sale Value, Item Count, Discount %), 5 slicers (Store, Month Year, Month Name, Year, Category), and 4 charts (area, column, pie, combo).
- **Page 3 — Extended Analysis** (2500×3000): 30 additional visuals — donut/bar/combo charts, a pivot table, and 8 slicers.
- 12 named DAX measures in total, including `Net_sales`, `Total_sale_val`, `Discount %`, `Avg Basket Value`, `MoM Growth %`, and `Discount Sales Ratio`.
- Uses one certified custom visual ("Advance Card") for the KPI tiles, and a custom theme layered over a base Power BI theme.

### Opening the report
1. Open `Goa_final_sales.pbix` in Power BI Desktop.
2. When prompted, point the data source at your own SQL Server instance/database hosting `dbo.final_sales`, or update the existing data source credentials (**Home → Transform data → Data source settings**).
3. Refresh the report.

## Notebook (`Goa_data_project.ipynb`)

### Prerequisites
```bash
pip install pandas numpy matplotlib seaborn scipy scikit-learn joblib pyodbc squarify
```
You'll also need the **ODBC Driver 17 for SQL Server** installed, and network access to the SQL Server instance hosting `dbo.final_sales`.

### Before running
The connection cell is hardcoded to a specific machine:
```python
connection = ("Driver={ODBC Driver 17 for SQL Server};"
              "Server=ITDSTANDBY-LAP\\MSSQLSERVER01;"
              "Database=Sales_New;"
              "Trusted_Connection=yes;")
```
Update `Server` and `Database` to match your own environment before running (better yet, move these into environment variables / a `.env` file so the notebook is portable across machines).

### What it does, in order
1. **Load** — pulls the full table via `pyodbc` (bypasses Excel's row limits).
2. **Explore** — shape, dtypes, category/sub-category value counts.
3. **Clean** — nulls in `DISCOUNT` → 0, nulls in `SALEVAL` → median, duplicate rows dropped.
4. **Store & category analysis** — top stores, top products, most-frequently-bought items.
5. **Time-based analysis** — MoM growth, year-by-category trends, weekly trend, time-of-day (Morning/Afternoon/Night) segmentation, top sales days.
6. **Outlier/anomaly detection** — Winsorization, IQR, MAD z-score, and Isolation Forest, combined into a 2-of-3 consensus flag.
7. **Store‑SKU feature engineering** — value/quantity totals, active days, recency, average monthly quantity, coefficient of variation of monthly quantity.
8. **ABC classification** (Pareto 70/20/10 by value) and **XYZ classification** (demand stability by coefficient of variation).
9. **KMeans clustering** (k=3) → re-mapped to **Top / Mid / Tail** segments by average value.
10. **Train/test split**, **model comparison** (Logistic Regression, Random Forest, Gradient Boosting via 5-fold CV), **hyperparameter tuning** (GridSearchCV on Random Forest), and **final model evaluation**.
11. **Export** — segmentation table to CSV, model + encoder + feature list to `.pkl`.

### Outputs produced by the notebook
```
store_sku_segmentation.csv       # STORE, itemid, ABC, XYZ, ABC_XYZ, demand_class,
                                  # ranks, and final Segment (Top/Mid/Tail) per store-SKU
product_segmentation_model.pkl   # trained classifier
segment_label_encoder.pkl        # Top/Mid/Tail <-> 0/1/2 mapping
segment_feature_cols.pkl         # exact feature column order the model expects
```

**Grain assumption:** one row per `(STORE, itemid)` pair. To get SKU-level segmentation pooled across all stores instead, drop `STORE` from the `groupby` in the feature-engineering cell — everything downstream still works unchanged.

## Full documentation

See **`Goa_Sales_Project_Documentation.pdf`** for the complete write-up, including the full SSMS schema screenshot, every dashboard visual and its fields, and a section-by-section notebook walkthrough.
