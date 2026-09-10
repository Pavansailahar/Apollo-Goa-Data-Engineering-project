/* ============================================================================
   GOLD LAYER  —  silver.vw_sales  ->  gold.* (dimensions + business marts)
   Platform: SQL Server / Azure SQL (T-SQL)
   Materialization: VIEW (query-time only, no physical load/refresh logic)

   Run silver_layer.sql first — every view below depends on silver.vw_sales.
============================================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO

-- ---------------------------------------------------------------------------
-- DIMENSION: Store
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_dim_store
AS
SELECT DISTINCT store_id
FROM silver.vw_sales
WHERE store_id IS NOT NULL;
GO

-- ---------------------------------------------------------------------------
-- DIMENSION: Item (product master, one row per item_id)
-- Minor name/attribute variants for the same item_id are collapsed with MAX().
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_dim_item
AS
SELECT
    item_id,
    MAX(item_name)     AS item_name,
    MAX(category)       AS category,
    MAX(sub_category)   AS sub_category,
    MAX(pack_size)       AS pack_size,
    MAX(generic_flag)    AS generic_flag
FROM silver.vw_sales
WHERE item_id IS NOT NULL
GROUP BY item_id;
GO

-- ---------------------------------------------------------------------------
-- DIMENSION: Customer group
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_dim_customer_group
AS
SELECT DISTINCT cust_group_id
FROM silver.vw_sales
WHERE cust_group_id IS NOT NULL;
GO

-- ---------------------------------------------------------------------------
-- DIMENSION: Date (derived — one row per calendar day present in the data)
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_dim_date
AS
SELECT DISTINCT
    bill_date,
    YEAR(bill_date)                AS bill_year,
    MONTH(bill_date)                AS bill_month,
    DATENAME(MONTH, bill_date)      AS bill_month_name,
    DATEPART(QUARTER, bill_date)    AS bill_quarter,
    DATENAME(WEEKDAY, bill_date)    AS bill_day_name,
    bill_month_start
FROM silver.vw_sales
WHERE bill_date IS NOT NULL;
GO

-- ---------------------------------------------------------------------------
-- FACT MART: Daily sales by store & category
-- Grain: one row per store, per calendar day, per category/sub-category
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_fact_sales_daily
AS
SELECT
    bill_date,
    store_id,
    category,
    sub_category,
    COUNT(DISTINCT bill_no)                                    AS bill_count,
    SUM(CASE WHEN is_return = 0 THEN sale_qty ELSE 0 END)       AS units_sold,
    SUM(CASE WHEN is_return = 1 THEN -sale_qty ELSE 0 END)      AS units_returned,
    SUM(sale_value)                                             AS net_sales_value,
    SUM(gross_sale_value)                                       AS gross_sales_value,
    SUM(discount_amt)                                           AS total_discount,
    CASE WHEN SUM(gross_sale_value) = 0 THEN 0
         ELSE ROUND(SUM(discount_amt) / SUM(gross_sale_value) * 100, 2)
    END                                                          AS discount_pct
FROM silver.vw_sales
GROUP BY bill_date, store_id, category, sub_category;
GO

-- ---------------------------------------------------------------------------
-- MART: Monthly store performance summary
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_sales_summary_monthly
AS
SELECT
    bill_month_start,
    store_id,
    COUNT(DISTINCT bill_no)                                     AS total_bills,
    SUM(sale_qty)                                               AS total_units,
    SUM(sale_value)                                             AS total_net_sales,
    SUM(discount_amt)                                           AS total_discount,
    CASE WHEN COUNT(DISTINCT bill_no) = 0 THEN 0
         ELSE ROUND(SUM(sale_value) * 1.0 / COUNT(DISTINCT bill_no), 2)
    END                                                          AS avg_bill_value
FROM silver.vw_sales
GROUP BY bill_month_start, store_id;
GO

-- ---------------------------------------------------------------------------
-- MART: Top-selling items (ranked by net sales value, returns excluded)
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_top_selling_items
AS
SELECT
    item_id,
    item_name,
    category,
    sub_category,
    SUM(sale_qty)                               AS total_units_sold,
    SUM(sale_value)                              AS total_net_sales,
    RANK() OVER (ORDER BY SUM(sale_value) DESC)  AS sales_rank
FROM silver.vw_sales
WHERE is_return = 0
GROUP BY item_id, item_name, category, sub_category;
GO

-- ---------------------------------------------------------------------------
-- MART: Discount impact by category / sub-category
-- ---------------------------------------------------------------------------
CREATE OR ALTER VIEW gold.vw_discount_analysis
AS
SELECT
    category,
    sub_category,
    SUM(gross_sale_value)                       AS gross_sales,
    SUM(discount_amt)                            AS total_discount,
    SUM(sale_value)                              AS net_sales,
    CASE WHEN SUM(gross_sale_value) = 0 THEN 0
         ELSE ROUND(SUM(discount_amt) / SUM(gross_sale_value) * 100, 2)
    END                                           AS discount_pct
FROM silver.vw_sales
GROUP BY category, sub_category;
GO