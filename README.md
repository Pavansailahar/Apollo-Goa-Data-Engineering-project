# Goa Retail Sales Analytics — Internship Project

End-to-end retail analytics project for Apollo Pharmacy's Goa store network: raw
POS extracts consolidated in SQL Server, re-modeled through a bronze/silver/gold
medallion architecture, mirrored into Databricks (Delta Lake + PySpark) for
business-question SQL and per-store sales forecasting, explored/modeled in a
Python notebook (EDA, anomaly detection, store-SKU segmentation), and surfaced
through both a Power BI report and a standalone web dashboard.

**Live dashboard:** https://claude.ai/code/artifact/5e9c15d2-8e15-4cc9-9042-cba050d5abfd
**Dashboard repo:** https://github.com/Pavansailahar/Apollo-Sales-Dashboard

> **Naming note:** the raw consolidated table is `dbo.final_sales` in SQL
> Server — 7,176,819 rows × 17 columns, spanning `2024-01-01` to
> `2026-06-30` across 58 Goa stores. Every layer in this project traces back
> to that one table.

---

## Pipeline at a glance

```
Raw Excel extracts (12 monthly files)
        │
        ▼
SQL Server  dbo.final_sales   (7,176,819 rows × 17 cols)
        │
        ├──────────────────────────────┐
        ▼                               ▼
SQL medallion architecture        Goa_final_sales.pbix
(bronze.vw_sales →                (Power BI dashboard,
 silver.vw_sales →                 modeled on this data's
 gold.vw_* marts)                  look — see its own docs)
        │
        ▼
sql_to_parquet.ipynb  →  .Parquet files/  (bronze, silver, gold marts)
        │
        ▼
Databricks  (Unity Catalog volumes → Delta tables)
  BronzeLayer.ipynb → SilverLayer.ipynb → GoldLayer.ipynb
        │
        ├──▶ Business questions.ipynb   (11 SQL business-question queries)
        └──▶ Databricks Forecasting.ipynb (Prophet, per-store next-month forecast)

python files and notebooks/Goa_data_project.ipynb
  (independent path: SQL Server → pandas → EDA, anomaly detection,
   ABC/XYZ + KMeans store-SKU segmentation, classifier)
        │
        ▼
apollo sales dashboard deploy/  (web dashboard built from the notebook's
                                  own output, documented number-by-number
                                  in its DATA_README.md)
```

One consolidated SQL Server table feeds every downstream artifact in this
repo; the SQL, Databricks, Python/ML, Power BI, and web-dashboard paths each
read from it (or a derivative of it) independently.

---

## Repository structure

| Path | What it is |
|---|---|
| [`SQL medallion architecture/`](SQL%20medallion%20architecture) | T-SQL views implementing bronze → silver → gold on top of `dbo.final_sales` |
| [`sql_to_parquet.ipynb`](sql_to_parquet.ipynb) | Exports the bronze/silver/gold SQL views to local Parquet files |
| [`.Parquet files/`](.Parquet%20files) | The exported Parquet output (bronze, silver, gold dimension & fact tables) |
| [`Databricks/`](Databricks) | Notebooks that load the Parquet files into Databricks as Delta tables, run business-question SQL, and forecast next-month sales per store |
| [`python files and notebooks/`](python%20files%20and%20notebooks) | `Goa_data_project.ipynb` — SQL Server → pandas EDA, cleaning, anomaly detection, and a full ABC/XYZ + KMeans store-SKU segmentation/classifier pipeline (own [README](python%20files%20and%20notebooks/README.md)) |
| [`Goa_final_sales.pbix`](Goa_final_sales.pbix) | Power BI Desktop report — KPI dashboard + extended analysis built on `final_sales` |
| [`apollo sales dashboard deploy/`](apollo%20sales%20dashboard%20deploy) | Standalone HTML/JS dashboard (deployed as a Claude Artifact) recreating the Power BI look, backed entirely by `Goa_data_project.ipynb`'s output — see its [DATA_README.md](apollo%20sales%20dashboard%20deploy/DATA_README.md) for a number-by-number data lineage |
| [`Goa_Sales_Project_Documentation.pdf`](Goa_Sales_Project_Documentation.pdf) | Full written documentation: SSMS schema, every dashboard visual and field, section-by-section notebook walkthrough |
| [`Databricks.zip`](Databricks.zip) | Archived copy of the `Databricks/` folder |

---

## 1. Data source: `dbo.final_sales`

17 columns, ~71.76 lakh (7.18M) rows, one row per item line on one bill:

| Column | Type | What it holds |
|---|---|---|
| `STORE` | smallint | Store code — one of 58 Goa outlets |
| `custgroup` | int | Customer group / loyalty segment code (`0` = walk-in) |
| `itemid` | nvarchar | SKU code |
| `itemname` | nvarchar | Product name as billed |
| `ctg` / `subctg` | nvarchar | Category (7 values: PHARMA, FMCG, PRIVATE LABEL, SURGICAL, CIRCLE SUBSCRIPTION, AYURVEDIC, STATIONERY) / sub-category (141 values) |
| `packsize` | smallint | Units per pack |
| `Generic_Flag` | nvarchar | Generic vs. branded flag |
| `BILLNO` | nvarchar | Bill/invoice number |
| `BILLDATETIME` | datetime2 | Full transaction timestamp |
| `BILLDATE` | date | Transaction date |
| `SALEQTY` | int | Quantity sold (can be negative — returns) |
| `SALEVAL` | float | Sale value in ₹ (can be negative — returns/credit notes) |
| `DISCOUNT` | float | Discount amount in ₹ (can be negative) |
| `BILLS` | tinyint | Per-line bill-count flag |
| `MAXSALEQTY` | int | Reference/benchmark max historical quantity for the SKU |
| `OFFERFLAG` | nvarchar | Promotional-offer flag |

`dbo.final_sales` itself is the union of 12 monthly source tables
(`FIRSTDATA` … `TWELVETHDATA`), confirmed by file-size matching; the
commented-out block at the bottom of `bronze upload.sql` shows how to
rebuild it from scratch if needed.

## 2. SQL medallion architecture (`SQL medallion architecture/`)

Three T-SQL scripts, run in order, each layer a set of views (query-time
only — no physical load/refresh job):

1. **[`bronze upload.sql`](SQL%20medallion%20architecture/bronze%20upload.sql)** — `bronze.vw_sales`: a straight pass-through of `dbo.final_sales`, just namespaced into its own schema.
2. **[`silver upload.sql`](SQL%20medallion%20architecture/silver%20upload.sql)** — `silver.vw_sales`: cleans and standardizes bronze —
   - literal `'NULL'` strings → real `NULL` (`Generic_Flag`, `OFFERFLAG`, `MAXSALEQTY`)
   - trims/upper-cases text keys (`item_id`, `bill_no`, `category`, `sub_category`)
   - de-dupes on the natural key `(store, bill_no, item_id, bill_datetime)`
   - flags negative-value rows as `is_return` instead of discarding them
   - derives `gross_sale_value = sale_value + discount_amt` and `bill_month_start`
3. **[`gold upload.sql`](SQL%20medallion%20architecture/gold%20upload.sql)** — business-ready dimension and fact views on top of silver:
   - `gold.vw_dim_store`, `gold.vw_dim_item`, `gold.vw_dim_customer_group`, `gold.vw_dim_date`
   - `gold.vw_fact_sales_daily` — daily grain by store/category/sub-category
   - `gold.vw_sales_summary_monthly` — monthly grain by store
   - `gold.vw_top_selling_items` — ranked by net sales value
   - `gold.vw_discount_analysis` — discount % by category/sub-category

## 3. Parquet export → Databricks (`sql_to_parquet.ipynb`, `.Parquet files/`, `Databricks/`)

`sql_to_parquet.ipynb` connects to the same SQL Server instance and exports
`bronze.vw_sales`, `silver.vw_sales`, and every `gold.*` view straight to
Parquet in `.Parquet files/` (a copy of the same notebook also lives in
`python files and notebooks/`).

Those files are then loaded into Databricks (Unity Catalog volumes under
`pharmacy_sales/{bronze,silver,gold}/…`) and written out as managed Delta
tables:

| Notebook | Does |
|---|---|
| [`BronzeLayer.ipynb`](Databricks/BronzeLayer.ipynb) | Reads `bronze_vw_sales.parquet`, normalizes `BILLDATETIME` precision (nanosecond → microsecond, via PyArrow) for Spark compatibility, writes table `bronze_vw_sales` |
| [`SilverLayer.ipynb`](Databricks/SilverLayer.ipynb) | Same pattern for `silver_vw_sales.parquet` → table `silver_vw_sales` |
| [`GoldLayer.ipynb`](Databricks/GoldLayer.ipynb) | Loads every gold Parquet mart, inspects schema/row counts |
| [`Business questions.ipynb`](Databricks/Business%20questions.ipynb) | 11 SQL business-question queries over the gold tables — monthly net sales & bill trend, sales/bills per store, revenue % by category, top/bottom 20 items, generic-vs-branded PHARMA split, discount % by category, return rate by store/category, avg. bill value by store and by customer group |
| [`Databricks Forecasting.ipynb`](Databricks/Databricks%20Forecasting.ipynb) | Runs **Prophet** per store (in parallel, via `applyInPandas`) over `gold_vw_sales_summary_monthly` to predict next month's net sales with confidence bounds, compares the forecast to the latest actual month, saves `pharmacy_sales.gold.forecast_store_next_month`, and charts predicted % change per store |
| [`Databricks Outpus/`](Databricks/Databricks%20Outpus) | Screenshots of the Databricks Jobs runs (list, timeline, run graphs) that executed this pipeline |

## 4. Python EDA & segmentation (`python files and notebooks/`)

`Goa_data_project.ipynb` is a separate, self-contained path: it connects
directly to SQL Server (`ITDSTANDBY-LAP\MSSQLSERVER01`, database
`Sales_New`) and pulls `final_sales` into pandas. See its own
[README](python%20files%20and%20notebooks/README.md) for prerequisites and
full step list; in short, it runs:

1. Load, explore, clean (`DISCOUNT` nulls → 0, `SALEVAL` nulls → median, dedupe check)
2. Store/category/product analysis and time-based trends (MoM growth, time-of-day split, top sales days)
3. Outlier detection — Winsorization, IQR, MAD z-score, Isolation Forest (2-of-3 consensus)
4. Store-SKU feature engineering → ABC classification (Pareto 70/20/10) + XYZ classification (demand stability)
5. KMeans clustering (k=3) → Top / Mid / Tail segments
6. Train/test split, model comparison (Logistic Regression, Random Forest, Gradient Boosting, 5-fold CV), GridSearchCV tuning, final evaluation
7. Export: `store_sku_segmentation.csv` + trained model/encoder/feature-list `.pkl` files

This notebook's own rendered output is the **sole data source** for both the
Power BI dashboard's visual style reference and every number on the web
dashboard (see §6 below) — nothing on either dashboard is recomputed
independently of it.

## 5. Power BI dashboard (`Goa_final_sales.pbix`)

- **Page 1 — Main Dashboard** (1280×720): 4 KPI cards (Net Sales, Total Sale Value, Item Count, Discount %), 5 slicers (Store, Month Year, Month Name, Year, Category), 4 charts (area, column, pie, combo)
- **Page 3 — Extended Analysis** (2500×3000): 30 additional visuals, a pivot table, 8 slicers
- 12 named DAX measures (`Net_sales`, `Total_sale_val`, `Discount %`, `Avg Basket Value`, `MoM Growth %`, `Discount Sales Ratio`, …)
- One certified custom visual ("Advance Card") for KPI tiles, custom theme

To open: launch `Goa_final_sales.pbix` in Power BI Desktop, then repoint the
data source at your own SQL Server instance/database (**Home → Transform
data → Data source settings**) and refresh.

## 6. Web dashboard (`apollo sales dashboard deploy/`)

A standalone HTML/JS recreation of the Power BI dashboard's look, published
as a Claude Artifact and pushed to
[github.com/Pavansailahar/Apollo-Sales-Dashboard](https://github.com/Pavansailahar/Apollo-Sales-Dashboard).
Every figure it shows is transcribed directly from `Goa_data_project.ipynb`'s
own rendered cell output (not recomputed) and cross-checked with five
internal reconciliation checks before publishing. Its
[DATA_README.md](apollo%20sales%20dashboard%20deploy/DATA_README.md) is the
authoritative, number-by-number account of where every KPI, chart, and
anomaly-detection figure on it comes from, what cleaning was applied, and
what was deliberately left out (e.g. the segmentation pipeline's cells had
no saved output as of the snapshot date, so it isn't represented on the
dashboard).

## 7. Full documentation

[`Goa_Sales_Project_Documentation.pdf`](Goa_Sales_Project_Documentation.pdf)
has the complete write-up: the SSMS schema screenshot, every dashboard
visual and its backing fields, and a section-by-section walkthrough of
`Goa_data_project.ipynb`.

---

## Prerequisites

- **SQL Server** with `dbo.final_sales` loaded, plus the bronze/silver/gold views from `SQL medallion architecture/` applied
- **ODBC Driver 17 for SQL Server** (for `sql_to_parquet.ipynb` and `Goa_data_project.ipynb`)
- **Python** — `pandas numpy matplotlib seaborn scipy scikit-learn joblib pyodbc squarify`
- **Databricks workspace** with Unity Catalog access (volumes under `pharmacy_sales/…`), plus `prophet` for the forecasting notebook
- **Power BI Desktop** to open `Goa_final_sales.pbix`

All SQL Server connection strings in these notebooks are hardcoded to
`ITDSTANDBY-LAP\MSSQLSERVER01` / database `Sales_New` — update `Server` and
`Database` (ideally moved to environment variables) before running on a
different machine.

## Known limitations

- The `.pbix` file's internal `DataModel` (VertiPaq/xVelocity format) could not be parsed in this environment (`pbixray` unreachable from the sandboxed package mirror), so it contributed only its visual style, not any extracted numbers, to the web dashboard.
- The store-SKU segmentation pipeline (ABC/XYZ, KMeans, classifier) in `Goa_data_project.ipynb` is fully built but, as of the last dashboard snapshot, hadn't been executed to produce saved output — so it isn't represented on either dashboard yet.
- Four charts on the web dashboard (MoM growth, year-wise category trend, top-10 products by value/quantity) are embedded as the notebook's own rendered images rather than redrawn, because their exact per-bar values were never printed as text in the notebook.
