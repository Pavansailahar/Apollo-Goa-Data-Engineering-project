/* ============================================================================
   BRONZE LAYER  —  dbo.final_sales  ->  bronze.vw_sales
   Platform: SQL Server / Azure SQL (T-SQL)
   Materialization: VIEW (query-time only, no physical load/refresh logic)

   PURPOSE
   -------
   Bronze is the raw, as-ingested layer: no cleaning, no type fixes, no
   dedup, no derived columns. This view just gives the raw feed a stable
   name in its own schema (bronze.vw_sales), so Silver and Gold read from
   "bronze.*" instead of reaching directly into dbo.*. Same data as
   dbo.final_sales — just properly layered.

   SOURCE ASSUMPTION
   -----------------
   dbo.final_sales already holds the union of the 12 monthly extracts
   (FIRSTDATA ... TWELVETHDATA) — confirmed earlier by file size (its size
   matches the sum of the 12 monthly tables). The commented-out block at the
   bottom shows how to rebuild that union from scratch if you ever need to.
============================================================================ */

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze')
    EXEC('CREATE SCHEMA bronze');
GO

CREATE OR ALTER VIEW bronze.vw_sales
AS
SELECT
    STORE,
    custgroup,
    itemid,
    itemname,
    ctg,
    subctg,
    packsize,
    Generic_Flag,
    BILLNO,
    BILLDATETIME,
    SALEQTY,
    BILLDATE,
    SALEVAL,
    DISCOUNT,
    BILLS,
    MAXSALEQTY,
    OFFERFLAG
FROM dbo.final_sales;
GO

/* ---------------------------------------------------------------------------
   REFERENCE ONLY — not run automatically. Uncomment and run instead of the
   view above only if dbo.final_sales ever needs to be rebuilt directly from
   the 12 monthly tables (all 12 share MAXSALEQTY as text, so the UNION ALL
   is type-safe as written):

CREATE OR ALTER VIEW bronze.vw_sales
AS
SELECT * FROM dbo.FIRSTDATA     UNION ALL
SELECT * FROM dbo.SECONDDATA    UNION ALL
SELECT * FROM dbo.THIRDDATA     UNION ALL
SELECT * FROM dbo.FOURTHDATA    UNION ALL
SELECT * FROM dbo.FIFTHDATA     UNION ALL
SELECT * FROM dbo.SIXTHDATA     UNION ALL
SELECT * FROM dbo.SEVENTHDATA   UNION ALL
SELECT * FROM dbo.EIGHTHDATA    UNION ALL
SELECT * FROM dbo.NINENTHDATA   UNION ALL
SELECT * FROM dbo.TENTHDATA     UNION ALL
SELECT * FROM dbo.ELEVENTHDATA  UNION ALL
SELECT * FROM dbo.TWELVETHDATA;
GO
--------------------------------------------------------------------------- */