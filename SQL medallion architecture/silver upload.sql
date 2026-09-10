/* ============================================================================
   SILVER LAYER  —  dbo.final_sales (Bronze)  ->  silver.vw_sales
   Platform: SQL Server / Azure SQL (T-SQL)
   Materialization: VIEW (query-time only, no physical load/refresh logic)

   BRONZE SOURCE ASSUMPTION
   ------------------------
   dbo.final_sales is treated as Bronze. Its size (~1.45 GB) matches the sum
   of the 12 monthly raw extracts in the same database (FIRSTDATA ...
   TWELVETHDATA), so it is being treated here as the already-unioned raw
   sales feed for the year. All 13 tables share this schema:
     STORE, custgroup, itemid, itemname, ctg, subctg, packsize,
     Generic_Flag, BILLNO, BILLDATETIME, SALEQTY, BILLDATE, SALEVAL,
     DISCOUNT, BILLS, MAXSALEQTY, OFFERFLAG
   Grain: one row = one item line on one bill.

   DATA QUALITY ISSUES HANDLED HERE (found by sampling the raw data)
   -------------------------------------------------------------------------
   1. Generic_Flag / OFFERFLAG / MAXSALEQTY contain the literal string
      'NULL' in many rows instead of a true SQL NULL -> converted to real
      NULLs below.
   2. itemid / BILLNO / itemname / ctg / subctg carry stray leading/trailing
      whitespace and inconsistent casing -> trimmed; itemid/BILLNO/ctg/
      sub_category upper-cased since they act as codes/keys.
   3. BILLNO formats are inconsistent across source POS systems (e.g.
      'CR0000964' vs a pure numeric string like '100043475'). Both are kept
      as-is (trimmed) since they are valid identifiers from different
      sources — flagged via bill_no_source_type for traceability.
   4. MAXSALEQTY's data type is inconsistent across the raw monthly tables
      (text in most, int in final_sales) -> defensively TRY_CAST to INT and
      strip literal 'NULL' text so this view stays safe even if pointed at
      one of the raw monthly tables instead.
   5. The monthly union can produce duplicate rows -> removed via a
      natural-key de-dup (store, bill_no, item_id, bill_datetime), keeping
      one row per key.
   6. Negative SALEQTY / SALEVAL are kept (not discarded) but flagged via
      is_return, since they represent real return/refund events, not bad
      data.

   ASSUMPTION TO REVISIT: SALEVAL is treated as the net billed value and
   DISCOUNT as the amount subtracted from a gross price, so
   gross_sale_value = sale_value + discount_amt. If your source defines
   SALEVAL as gross (pre-discount) instead, flip the sign in gross_sale_value
   and adjust the Gold-layer discount % formulas accordingly.
============================================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO

CREATE OR ALTER VIEW silver.vw_sales
AS
WITH cleaned AS (
    SELECT
        TRY_CAST(f.STORE AS SMALLINT)                                        AS store_id,
        TRY_CAST(f.custgroup AS INT)                                         AS cust_group_id,
        UPPER(LTRIM(RTRIM(f.itemid)))                                        AS item_id,
        NULLIF(LTRIM(RTRIM(f.itemname)), '')                                 AS item_name,
        NULLIF(UPPER(LTRIM(RTRIM(f.ctg))), '')                               AS category,
        NULLIF(UPPER(LTRIM(RTRIM(f.subctg))), '')                            AS sub_category,
        TRY_CAST(f.packsize AS SMALLINT)                                     AS pack_size,
        CASE
            WHEN UPPER(LTRIM(RTRIM(f.Generic_Flag))) IN ('NULL', '') THEN NULL
            ELSE UPPER(LTRIM(RTRIM(f.Generic_Flag)))
        END                                                                  AS generic_flag,
        UPPER(LTRIM(RTRIM(f.BILLNO)))                                        AS bill_no,
        CASE
            WHEN LTRIM(RTRIM(f.BILLNO)) LIKE '[A-Za-z]%' THEN 'ALPHA_PREFIXED'
            ELSE 'NUMERIC'
        END                                                                  AS bill_no_source_type,
        f.BILLDATETIME                                                      AS bill_datetime,
        COALESCE(TRY_CAST(f.BILLDATE AS DATE), CAST(f.BILLDATETIME AS DATE)) AS bill_date,
        TRY_CAST(f.SALEQTY AS INT)                                           AS sale_qty,
        TRY_CAST(f.SALEVAL AS FLOAT)                                         AS sale_value,
        TRY_CAST(f.DISCOUNT AS FLOAT)                                        AS discount_amt,
        TRY_CAST(f.BILLS AS TINYINT)                                        AS bill_count,
        TRY_CAST(
            CASE WHEN UPPER(LTRIM(RTRIM(CAST(f.MAXSALEQTY AS NVARCHAR(50))))) = 'NULL'
                 THEN NULL
                 ELSE CAST(f.MAXSALEQTY AS NVARCHAR(50))
            END AS INT)                                                     AS max_sale_qty,
        CASE
            WHEN UPPER(LTRIM(RTRIM(f.OFFERFLAG))) IN ('NULL', '') THEN NULL
            ELSE UPPER(LTRIM(RTRIM(f.OFFERFLAG)))
        END                                                                  AS offer_flag,
        ROW_NUMBER() OVER (
            PARTITION BY f.STORE, LTRIM(RTRIM(f.BILLNO)), LTRIM(RTRIM(f.itemid)), f.BILLDATETIME
            ORDER BY f.BILLDATETIME DESC
        ) AS rn
    FROM dbo.final_sales AS f
    WHERE f.BILLNO IS NOT NULL
      AND f.itemid IS NOT NULL
)
SELECT
    store_id,
    cust_group_id,
    item_id,
    item_name,
    category,
    sub_category,
    pack_size,
    generic_flag,
    bill_no,
    bill_no_source_type,
    bill_datetime,
    bill_date,
    DATEFROMPARTS(YEAR(bill_date), MONTH(bill_date), 1)                     AS bill_month_start,
    sale_qty,
    sale_value,
    discount_amt,
    ROUND(sale_value + ISNULL(discount_amt, 0), 2)                          AS gross_sale_value,
    CASE WHEN sale_qty < 0 OR sale_value < 0 THEN 1 ELSE 0 END              AS is_return,
    bill_count,
    max_sale_qty,
    offer_flag
FROM cleaned
WHERE rn = 1;
GO

EXEC silver.vw_sales