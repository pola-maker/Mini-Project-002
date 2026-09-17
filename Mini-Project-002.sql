IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'bronze')
    EXEC('CREATE SCHEMA bronze');
GO        
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'silver')
    EXEC('CREATE SCHEMA silver');
GO
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'gold')
    EXEC('CREATE SCHEMA gold');
GO

-- Staging Layer

DROP TABLE IF EXISTS staging_superstore;

CREATE TABLE staging_superstore (
    row_id NVARCHAR(255),
    order_id NVARCHAR(255),
    order_date NVARCHAR(255),
    ship_date NVARCHAR(255),
    ship_mode NVARCHAR(255),
    customer_id NVARCHAR(255),
    customer_name NVARCHAR(255),
    segment NVARCHAR(255),
    country NVARCHAR(255),
    city NVARCHAR(255),
    state NVARCHAR(255),
    postal_code NVARCHAR(255),
    region NVARCHAR(255),
    product_id NVARCHAR(255),
    category NVARCHAR(255),
    sub_category NVARCHAR(255),
    product_name NVARCHAR(255),
    sales NVARCHAR(255),
    quantity NVARCHAR(255),
    discount NVARCHAR(255),
    profit NVARCHAR(255),
);
GO

TRUNCATE TABLE staging_superstore;

BULK INSERT staging_superstore
FROM 'D:\Mini-project-002\Central_Superstore.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    CODEPAGE = '65001',
    MAXERRORS = 0,
    ERRORFILE = 'D:\Mini-project-002\Central_Superstore.xlsx_error_log'
);
GO

SELECT TOP 10 * FROM staging_superstore;

-- Bronze Layer: Raw Data Ingestion

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'bronze' AND t.name = 'central_superstore')
BEGIN
    CREATE TABLE bronze.central_superstore (
        bronze_id INT IDENTITY(1,1) PRIMARY KEY,
        row_id NVARCHAR(255),
        order_id NVARCHAR(255),
        order_date NVARCHAR(255),
        ship_date NVARCHAR(255),
        ship_mode NVARCHAR(255),
        customer_id NVARCHAR(255),
        customer_name NVARCHAR(255),
        segment NVARCHAR(255),
        country NVARCHAR(255),
        city NVARCHAR(255),
        state NVARCHAR(255),
        postal_code NVARCHAR(255),
        region NVARCHAR(255),
        product_id NVARCHAR(255),
        category NVARCHAR(255),
        sub_category NVARCHAR(255),
        product_name NVARCHAR(500),
        sales NVARCHAR(255),
        quantity NVARCHAR(255),
        discount NVARCHAR(255),
        profit NVARCHAR(255),
        _ingested_at DATETIME DEFAULT GETDATE(),
        _source_batch NVARCHAR(100) DEFAULT 'Central_Superstore_Batch1'
    );
END;
GO

INSERT INTO bronze.central_superstore (
    row_id,
    order_id,
    order_date,
    ship_date,
    ship_mode,
    customer_id,
    customer_name,
    segment,
    country,
    city,
    state,
    postal_code,
    region,
    product_id,
    category,
    sub_category,
    product_name,
    sales,
    quantity,
    discount,
    profit
)
SELECT row_id, order_id, order_date, ship_date, ship_mode, customer_id, customer_name, segment, country, city, state, postal_code, region, product_id, category, sub_category, product_name, sales, quantity, discount, profit
FROM staging_superstore
EXCEPT
SELECT row_id, order_id, order_date, ship_date, ship_mode, customer_id, customer_name, segment, country, city, state, postal_code, region, product_id, category, sub_category, product_name, sales, quantity, discount, profit
FROM bronze.central_superstore;
GO

SELECT TOP 10 * FROM bronze.central_superstore ORDER BY bronze_id DESC;

-- Silver Layer: Cleansing and Transformation

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'silver' AND t.name = 'customers')
BEGIN
    CREATE TABLE silver.customers (
        customer_id NVARCHAR(20) NOT NULL PRIMARY KEY,
        customer_name NVARCHAR(100),
        segment NVARCHAR(50),
        has_missing_value BIT NOT NULL DEFAULT 0,
        has_invalid_value BIT NOT NULL DEFAULT 0,
        has_outlier_value BIT NOT NULL DEFAULT 0
    );
END;
GO

WITH cust_latest AS (
    SELECT 
        customer_id, customer_name, segment, bronze_id,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY bronze_id DESC) AS rn
    FROM bronze.central_superstore
    WHERE NULLIF(LTRIM(RTRIM(customer_id)), '') IS NOT NULL
),
cust_cleaned AS (
    SELECT 
        LTRIM(RTRIM(customer_id)) AS customer_id,
        NULLIF(LTRIM(RTRIM(customer_name)), '') AS customer_name,
        NULLIF(LTRIM(RTRIM(segment)), '') AS segment
    FROM cust_latest
    WHERE rn = 1
),
cust_flagged AS (
    SELECT 
        customer_id, customer_name, segment,
        CASE WHEN customer_name IS NULL OR segment IS NULL THEN 1 ELSE 0 END AS has_missing_value,
        CASE WHEN segment NOT IN ('Consumer', 'Corporate', 'Home Office') THEN 1 ELSE 0 END AS has_invalid_value,
        CAST(0 AS BIT) AS has_outlier_value
    FROM cust_cleaned
)
MERGE silver.customers AS tgt
USING cust_flagged AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED THEN
    UPDATE SET
        tgt.customer_name = src.customer_name,
        tgt.segment = src.segment,
        tgt.has_missing_value = src.has_missing_value,
        tgt.has_invalid_value = src.has_invalid_value,
        tgt.has_outlier_value = src.has_outlier_value
WHEN NOT MATCHED THEN
    INSERT (customer_id, customer_name, segment, has_missing_value, has_invalid_value, has_outlier_value)
    VALUES (src.customer_id, src.customer_name, src.segment, src.has_missing_value, src.has_invalid_value, src.has_outlier_value);
GO

SELECT TOP 10 * FROM silver.customers;

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'silver' AND t.name = 'locations')
BEGIN
    CREATE TABLE silver.locations (
        postal_code INT NOT NULL PRIMARY KEY,
        city NVARCHAR(100),
        state NVARCHAR(100),
        region NVARCHAR(50),
        country NVARCHAR(50),
        has_missing_value BIT NOT NULL DEFAULT 0,
        has_invalid_value BIT NOT NULL DEFAULT 0,
        has_outlier_value BIT NOT NULL DEFAULT 0
    );
END;
GO

WITH loc_latest AS (
    SELECT 
        postal_code, city, state, region, country, bronze_id,
        ROW_NUMBER() OVER (PARTITION BY postal_code ORDER BY bronze_id DESC) AS rn
    FROM bronze.central_superstore
    WHERE NULLIF(LTRIM(RTRIM(postal_code)), '') IS NOT NULL
),
loc_cleaned AS (
    SELECT 
        TRY_CAST(postal_code AS INT) AS postal_code,
        NULLIF(LTRIM(RTRIM(postal_code)), '') AS raw_postal_code,
        NULLIF(LTRIM(RTRIM(city)), '') AS city,
        NULLIF(LTRIM(RTRIM(state)), '') AS state,
        NULLIF(LTRIM(RTRIM(region)), '') AS region,
        NULLIF(LTRIM(RTRIM(country)), '') AS country
    FROM loc_latest
    WHERE rn = 1
),
loc_flagged AS (
    SELECT 
        postal_code, city, state, region, country,
        CASE WHEN city IS NULL OR state IS NULL OR country IS NULL THEN 1 ELSE 0 END AS has_missing_value,
        CASE WHEN raw_postal_code IS NOT NULL AND postal_code IS NULL THEN 1 ELSE 0 END AS has_invalid_value,
        CAST(0 AS BIT) AS has_outlier_value
    FROM loc_cleaned
    WHERE postal_code IS NOT NULL
)
MERGE silver.locations AS tgt
USING loc_flagged AS src
ON tgt.postal_code = src.postal_code
WHEN MATCHED THEN
    UPDATE SET
        tgt.city = src.city,
        tgt.state = src.state,
        tgt.region = src.region,
        tgt.country = src.country,
        tgt.has_missing_value = src.has_missing_value,
        tgt.has_invalid_value = src.has_invalid_value,
        tgt.has_outlier_value = src.has_outlier_value
WHEN NOT MATCHED THEN
    INSERT (postal_code, city, state, region, country, has_missing_value, has_invalid_value, has_outlier_value)
    VALUES (src.postal_code, src.city, src.state, src.region, src.country, src.has_missing_value, src.has_invalid_value, src.has_outlier_value);
GO

SELECT TOP 10 * FROM silver.locations;

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'silver' AND t.name = 'products')
BEGIN
    CREATE TABLE silver.products (
        product_bk NVARCHAR(300) NOT NULL PRIMARY KEY, -- Synthetic unique Natural Key (ID + Name)
        product_id NVARCHAR(50) NOT NULL,
        product_name NVARCHAR(255) NOT NULL,
        category NVARCHAR(50),
        sub_category NVARCHAR(50),
        has_missing_value BIT NOT NULL DEFAULT 0,
        has_invalid_value BIT NOT NULL DEFAULT 0,
        has_outlier_value BIT NOT NULL DEFAULT 0
    );
END;
GO

WITH prod_latest AS (
    SELECT 
        product_id, product_name, category, sub_category, bronze_id,
        ROW_NUMBER() OVER (
            PARTITION BY LTRIM(RTRIM(product_id)), LTRIM(RTRIM(product_name)) 
            ORDER BY bronze_id DESC
        ) AS rn
    FROM bronze.central_superstore
    WHERE NULLIF(LTRIM(RTRIM(product_id)), '') IS NOT NULL
),
prod_cleaned AS (
    SELECT 
        CONCAT(LTRIM(RTRIM(product_id)), '|', LTRIM(RTRIM(product_name))) AS product_bk,
        LTRIM(RTRIM(product_id)) AS product_id,
        LTRIM(RTRIM(product_name)) AS product_name,
        NULLIF(LTRIM(RTRIM(category)), '') AS category,
        NULLIF(LTRIM(RTRIM(sub_category)), '') AS sub_category
    FROM prod_latest
    WHERE rn = 1
),
prod_flagged AS (
    SELECT 
        product_bk, product_id, product_name, category, sub_category,
        CASE WHEN category IS NULL OR sub_category IS NULL THEN 1 ELSE 0 END AS has_missing_value,
        CASE WHEN category NOT IN ('Furniture', 'Office Supplies', 'Technology') THEN 1 ELSE 0 END AS has_invalid_value,
        CAST(0 AS BIT) AS has_outlier_value
    FROM prod_cleaned
)
MERGE silver.products AS tgt
USING prod_flagged AS src
ON tgt.product_bk = src.product_bk
WHEN MATCHED THEN
    UPDATE SET
        tgt.category = src.category,
        tgt.sub_category = src.sub_category,
        tgt.has_missing_value = src.has_missing_value,
        tgt.has_invalid_value = src.has_invalid_value,
        tgt.has_outlier_value = src.has_outlier_value
WHEN NOT MATCHED THEN
    INSERT (product_bk, product_id, product_name, category, sub_category, has_missing_value, has_invalid_value, has_outlier_value)
    VALUES (src.product_bk, src.product_id, src.product_name, src.category, src.sub_category, src.has_missing_value, src.has_invalid_value, src.has_outlier_value);
GO

SELECT TOP 10 * FROM silver.products;

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'silver' AND t.name = 'orders')
BEGIN
    CREATE TABLE silver.orders (
        row_id INT NOT NULL PRIMARY KEY,
        order_id NVARCHAR(50) NOT NULL,
        order_date DATE,
        ship_date DATE,
        ship_mode NVARCHAR(50),
        customer_id NVARCHAR(20),
        postal_code INT,
        product_bk NVARCHAR(300),
        sales DECIMAL(12,4),
        quantity INT,
        discount DECIMAL(6,4),
        profit DECIMAL(12,4),
        has_missing_value BIT NOT NULL DEFAULT 0,
        has_invalid_value BIT NOT NULL DEFAULT 0,
        has_outlier_value BIT NOT NULL DEFAULT 0
    );
END;
GO

WITH ord_latest AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY row_id ORDER BY bronze_id DESC) AS rn
    FROM bronze.central_superstore
    WHERE NULLIF(LTRIM(RTRIM(row_id)), '') IS NOT NULL
),
ord_cleaned AS (
    SELECT 
        TRY_CAST(row_id AS INT) AS row_id,
        LTRIM(RTRIM(order_id)) AS order_id,
        TRY_CAST(order_date AS DATE) AS order_date,
        NULLIF(LTRIM(RTRIM(order_date)), '') AS raw_order_date,
        TRY_CAST(ship_date AS DATE) AS ship_date,
        NULLIF(LTRIM(RTRIM(ship_date)), '') AS raw_ship_date,
        LTRIM(RTRIM(ship_mode)) AS ship_mode,
        LTRIM(RTRIM(customer_id)) AS customer_id,
        TRY_CAST(postal_code AS INT) AS postal_code,
        CONCAT(LTRIM(RTRIM(product_id)), '|', LTRIM(RTRIM(product_name))) AS product_bk,
        TRY_CAST(sales AS DECIMAL(12,4)) AS sales,
        NULLIF(LTRIM(RTRIM(sales)), '') AS raw_sales,
        TRY_CAST(quantity AS INT) AS quantity,
        NULLIF(LTRIM(RTRIM(quantity)), '') AS raw_quantity,
        TRY_CAST(discount AS DECIMAL(6,4)) AS discount,
        NULLIF(LTRIM(RTRIM(discount)), '') AS raw_discount,
        TRY_CAST(profit AS DECIMAL(12,4)) AS profit,
        NULLIF(LTRIM(RTRIM(profit)), '') AS raw_profit
    FROM ord_latest
    WHERE rn = 1
),
iqr_bounds AS (
    SELECT DISTINCT
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY sales) OVER () AS q1_sales,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY sales) OVER () AS q3_sales,
        PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY profit) OVER () AS q1_profit,
        PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY profit) OVER () AS q3_profit
    FROM ord_cleaned
    WHERE sales IS NOT NULL AND profit IS NOT NULL
),
ord_flagged AS (
    SELECT 
        c.row_id, c.order_id, c.order_date, c.ship_date, c.ship_mode,
        c.customer_id, c.postal_code, c.product_bk, c.sales, c.quantity, c.discount, c.profit,
        CASE WHEN 
            c.customer_id IS NULL OR c.order_date IS NULL OR c.sales IS NULL OR c.quantity IS NULL 
        THEN 1 ELSE 0 END AS has_missing_value,
        CASE WHEN 
            (c.raw_order_date IS NOT NULL AND c.order_date IS NULL)
            OR (c.raw_sales IS NOT NULL AND c.sales IS NULL)
            OR (c.sales IS NOT NULL AND c.sales < 0)
            OR (c.quantity IS NOT NULL AND c.quantity <= 0)
            OR (c.discount IS NOT NULL AND (c.discount < 0 OR c.discount > 1))
            OR (c.customer_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM silver.customers sc WHERE sc.customer_id = c.customer_id))
            OR (c.postal_code IS NOT NULL AND NOT EXISTS (SELECT 1 FROM silver.locations sl WHERE sl.postal_code = c.postal_code))
            OR (c.product_bk IS NOT NULL AND NOT EXISTS (SELECT 1 FROM silver.products sp WHERE sp.product_bk = c.product_bk))
        THEN 1 ELSE 0 END AS has_invalid_value,
        CASE WHEN 
            (c.sales IS NOT NULL AND (c.sales < b.q1_sales - 1.5*(b.q3_sales - b.q1_sales) OR c.sales > b.q3_sales + 1.5*(b.q3_sales - b.q1_sales)))
            OR (c.profit IS NOT NULL AND (c.profit < b.q1_profit - 1.5*(b.q3_profit - b.q1_profit) OR c.profit > b.q3_profit + 1.5*(b.q3_profit - b.q1_profit)))
        THEN 1 ELSE 0 END AS has_outlier_value
    FROM ord_cleaned c
    CROSS JOIN iqr_bounds b
    WHERE c.row_id IS NOT NULL
)
MERGE silver.orders AS tgt
USING ord_flagged AS src
ON tgt.row_id = src.row_id
WHEN MATCHED THEN
    UPDATE SET
        tgt.order_id = src.order_id,
        tgt.order_date = src.order_date,
        tgt.ship_date = src.ship_date,
        tgt.ship_mode = src.ship_mode,
        tgt.customer_id = src.customer_id,
        tgt.postal_code = src.postal_code,
        tgt.product_bk = src.product_bk,
        tgt.sales = src.sales,
        tgt.quantity = src.quantity,
        tgt.discount = src.discount,
        tgt.profit = src.profit,
        tgt.has_missing_value = src.has_missing_value,
        tgt.has_invalid_value = src.has_invalid_value,
        tgt.has_outlier_value = src.has_outlier_value
WHEN NOT MATCHED THEN
    INSERT (row_id, order_id, order_date, ship_date, ship_mode, customer_id, postal_code, product_bk, sales, quantity, discount, profit, has_missing_value, has_invalid_value, has_outlier_value)
    VALUES (src.row_id, src.order_id, src.order_date, src.ship_date, src.ship_mode, src.customer_id, src.postal_code, src.product_bk, src.sales, src.quantity, src.discount, src.profit, src.has_missing_value, src.has_invalid_value, src.has_outlier_value);
GO

SELECT TOP 10 * FROM silver.orders;

-- Gold Layer: Dimensional Tables

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'dim_customer')
BEGIN
    CREATE TABLE gold.dim_customer (
        customer_key INT IDENTITY(1,1) PRIMARY KEY,
        customer_id NVARCHAR(20) NOT NULL CONSTRAINT UQ_gold_dim_customer_id UNIQUE,
        customer_name NVARCHAR(100),
        segment NVARCHAR(50)
    );
END;
GO



IF NOT EXISTS (SELECT 1 FROM gold.dim_customer WHERE customer_key = -1)
BEGIN
    SET IDENTITY_INSERT gold.dim_customer ON;
    INSERT INTO gold.dim_customer (customer_key, customer_id, customer_name, segment)
    VALUES (-1, 'UNKNOWN', 'Unknown Customer', 'Unknown');
    SET IDENTITY_INSERT gold.dim_customer OFF;
END;
GO

MERGE gold.dim_customer AS tgt
USING silver.customers AS src
ON tgt.customer_id = src.customer_id
WHEN MATCHED THEN
    UPDATE SET 
        tgt.customer_name = src.customer_name,
        tgt.segment = src.segment
WHEN NOT MATCHED THEN
    INSERT (customer_id, customer_name, segment)
    VALUES (src.customer_id, src.customer_name, src.segment);
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'dim_location')
BEGIN
    CREATE TABLE gold.dim_location (
        location_key INT IDENTITY(1,1) PRIMARY KEY,
        postal_code INT NOT NULL CONSTRAINT UQ_gold_dim_location_pc UNIQUE,
        city NVARCHAR(100),
        state NVARCHAR(100),
        region NVARCHAR(50),
        country NVARCHAR(50)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM gold.dim_location WHERE location_key = -1)
BEGIN
    SET IDENTITY_INSERT gold.dim_location ON;
    INSERT INTO gold.dim_location (location_key, postal_code, city, state, region, country)
    VALUES (-1, -1, 'Unknown', 'Unknown', 'Unknown', 'Unknown');
    SET IDENTITY_INSERT gold.dim_location OFF;
END;
GO

MERGE gold.dim_location AS tgt
USING silver.locations AS src
ON tgt.postal_code = src.postal_code
WHEN MATCHED THEN
    UPDATE SET 
        tgt.city = src.city,
        tgt.state = src.state,
        tgt.region = src.region,
        tgt.country = src.country
WHEN NOT MATCHED THEN
    INSERT (postal_code, city, state, region, country)
    VALUES (src.postal_code, src.city, src.state, src.region, src.country);
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'dim_product')
BEGIN
    CREATE TABLE gold.dim_product (
        product_key INT IDENTITY(1,1) PRIMARY KEY,
        product_bk NVARCHAR(300) NOT NULL CONSTRAINT UQ_gold_dim_product_bk UNIQUE,
        product_id NVARCHAR(50) NOT NULL,
        product_name NVARCHAR(255) NOT NULL,
        category NVARCHAR(50),
        sub_category NVARCHAR(50)
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM gold.dim_product WHERE product_key = -1)
BEGIN
    SET IDENTITY_INSERT gold.dim_product ON;
    INSERT INTO gold.dim_product (product_key, product_bk, product_id, product_name, category, sub_category)
    VALUES (-1, 'UNKNOWN', 'UNKNOWN', 'Unknown Product', 'Unknown', 'Unknown');
    SET IDENTITY_INSERT gold.dim_product OFF;
END;
GO

MERGE gold.dim_product AS tgt
USING silver.products AS src
ON tgt.product_bk = src.product_bk
WHEN MATCHED THEN
    UPDATE SET 
        tgt.product_id = src.product_id,
        tgt.product_name = src.product_name,
        tgt.category = src.category,
        tgt.sub_category = src.sub_category
WHEN NOT MATCHED THEN
    INSERT (product_bk, product_id, product_name, category, sub_category)
    VALUES (src.product_bk, src.product_id, src.product_name, src.category, src.sub_category);
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'dim_date')
BEGIN
    CREATE TABLE gold.dim_date (
        date_key INT PRIMARY KEY,
        full_date DATE NOT NULL CONSTRAINT UQ_gold_dim_date_full UNIQUE,
        [year] SMALLINT,
        [quarter] TINYINT,
        [month] TINYINT,
        month_name NVARCHAR(12),
        [day] TINYINT,
        day_of_week TINYINT,
        day_name NVARCHAR(12),
        is_weekend BIT
    );
END;
GO

IF NOT EXISTS (SELECT 1 FROM gold.dim_date WHERE date_key = 19000101)
BEGIN
    INSERT INTO gold.dim_date (date_key, full_date, [year], [quarter], [month], month_name, [day], day_of_week, day_name, is_weekend)
    VALUES (19000101, '1900-01-01', 1900, 1, 1, 'Unknown', 1, 0, 'Unknown', 0);
END;
GO

DECLARE @min_date DATE, @max_date DATE;
SELECT @min_date = MIN(d), @max_date = MAX(d)
FROM (
    SELECT order_date AS d FROM silver.orders WHERE order_date IS NOT NULL
    UNION ALL
    SELECT ship_date AS d FROM silver.orders WHERE ship_date IS NOT NULL
) dt;

;WITH date_spine AS (
    SELECT @min_date AS d
    UNION ALL
    SELECT DATEADD(DAY, 1, d) FROM date_spine WHERE d < @max_date
)
INSERT INTO gold.dim_date (date_key, full_date, [year], [quarter], [month], month_name, [day], day_of_week, day_name, is_weekend)
SELECT 
    CONVERT(INT, FORMAT(d, 'yyyyMMdd')),
    d,
    YEAR(d),
    DATEPART(QUARTER, d),
    MONTH(d),
    DATENAME(MONTH, d),
    DAY(d),
    DATEPART(WEEKDAY, d),
    DATENAME(WEEKDAY, d),
    CASE WHEN DATENAME(WEEKDAY, d) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END
FROM date_spine
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_date dd WHERE dd.date_key = CONVERT(INT, FORMAT(d, 'yyyyMMdd')))
OPTION (MAXRECURSION 0);
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN sys.schemas s ON t.schema_id = s.schema_id WHERE s.name = 'gold' AND t.name = 'fact_orders')
BEGIN
    CREATE TABLE gold.fact_orders (
        row_id INT NOT NULL PRIMARY KEY,
        order_id NVARCHAR(50) NOT NULL,
        customer_key INT NOT NULL,
        location_key INT NOT NULL,
        product_key INT NOT NULL,
        order_date_key INT NOT NULL,
        ship_date_key INT NOT NULL,
        ship_mode NVARCHAR(50),
        sales DECIMAL(12,4),
        quantity INT,
        discount DECIMAL(6,4),
        profit DECIMAL(12,4),
        CONSTRAINT FK_gold_fact_customer FOREIGN KEY (customer_key) REFERENCES gold.dim_customer(customer_key),
        CONSTRAINT FK_gold_fact_location FOREIGN KEY (location_key) REFERENCES gold.dim_location(location_key),
        CONSTRAINT FK_gold_fact_product  FOREIGN KEY (product_key)  REFERENCES gold.dim_product(product_key),
        CONSTRAINT FK_gold_fact_odate    FOREIGN KEY (order_date_key) REFERENCES gold.dim_date(date_key),
        CONSTRAINT FK_gold_fact_sdate    FOREIGN KEY (ship_date_key)  REFERENCES gold.dim_date(date_key)
    );
END;
GO

MERGE gold.fact_orders AS tgt
USING (
    SELECT 
        o.row_id,
        o.order_id,
        ISNULL(dc.customer_key, -1) AS customer_key,
        ISNULL(dl.location_key, -1) AS location_key,
        ISNULL(dp.product_key, -1) AS product_key,
        ISNULL(CONVERT(INT, FORMAT(o.order_date, 'yyyyMMdd')), 19000101) AS order_date_key,
        ISNULL(CONVERT(INT, FORMAT(o.ship_date, 'yyyyMMdd')), 19000101) AS ship_date_key,
        o.ship_mode,
        o.sales,
        o.quantity,
        o.discount,
        o.profit
    FROM silver.orders o
    LEFT JOIN gold.dim_customer dc ON dc.customer_id = o.customer_id
    LEFT JOIN gold.dim_location dl ON dl.postal_code = o.postal_code
    LEFT JOIN gold.dim_product dp  ON dp.product_bk = o.product_bk
) AS src
ON tgt.row_id = src.row_id
WHEN MATCHED THEN
    UPDATE SET 
        tgt.order_id = src.order_id,
        tgt.customer_key = src.customer_key,
        tgt.location_key = src.location_key,
        tgt.product_key = src.product_key,
        tgt.order_date_key = src.order_date_key,
        tgt.ship_date_key = src.ship_date_key,
        tgt.ship_mode = src.ship_mode,
        tgt.sales = src.sales,
        tgt.quantity = src.quantity,
        tgt.discount = src.discount,
        tgt.profit = src.profit
WHEN NOT MATCHED THEN
    INSERT (row_id, order_id, customer_key, location_key, product_key, order_date_key, ship_date_key, ship_mode, sales, quantity, discount, profit)
    VALUES (src.row_id, src.order_id, src.customer_key, src.location_key, src.product_key, src.order_date_key, src.ship_date_key, src.ship_mode, src.sales, src.quantity, src.discount, src.profit);
GO

IF OBJECT_ID('gold.vw_dim_customer', 'V') IS NOT NULL DROP VIEW gold.vw_dim_customer;
GO
CREATE VIEW gold.vw_dim_customer AS
SELECT customer_id, customer_name, segment
FROM silver.customers
UNION ALL
SELECT 'UNKNOWN', 'Unknown Customer', 'Unknown';
GO

IF OBJECT_ID('gold.vw_dim_location', 'V') IS NOT NULL DROP VIEW gold.vw_dim_location;
GO
CREATE VIEW gold.vw_dim_location AS
SELECT postal_code, city, state, region, country
FROM silver.locations
UNION ALL
SELECT -1, 'Unknown', 'Unknown', 'Unknown', 'Unknown';
GO

IF OBJECT_ID('gold.vw_dim_product', 'V') IS NOT NULL DROP VIEW gold.vw_dim_product;
GO
CREATE VIEW gold.vw_dim_product AS
SELECT product_bk, product_id, product_name, category, sub_category
FROM silver.products
UNION ALL
SELECT 'UNKNOWN', 'UNKNOWN', 'Unknown Product', 'Unknown', 'Unknown';
GO

IF OBJECT_ID('gold.vw_dim_date', 'V') IS NOT NULL DROP VIEW gold.vw_dim_date;
GO
CREATE VIEW gold.vw_dim_date AS
SELECT 
    CONVERT(INT, FORMAT(d, 'yyyyMMdd')) AS date_key,
    d AS full_date,
    YEAR(d) AS [year],
    DATEPART(QUARTER, d) AS [quarter],
    MONTH(d) AS [month],
    DATENAME(MONTH, d) AS month_name,
    DAY(d) AS [day],
    DATEPART(WEEKDAY, d) AS day_of_week,
    DATENAME(WEEKDAY, d) AS day_name,
    CASE WHEN DATENAME(WEEKDAY, d) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END AS is_weekend
FROM (
    SELECT DISTINCT order_date AS d FROM silver.orders WHERE order_date IS NOT NULL
    UNION
    SELECT DISTINCT ship_date AS d FROM silver.orders WHERE ship_date IS NOT NULL
) AS dates
UNION ALL
SELECT 19000101, '1900-01-01', 1900, 1, 1, 'Unknown', 1, 0, 'Unknown', 0;
GO

IF OBJECT_ID('gold.vw_fact_orders', 'V') IS NOT NULL DROP VIEW gold.vw_fact_orders;
GO
CREATE VIEW gold.vw_fact_orders AS
SELECT 
    o.row_id,
    o.order_id,
    ISNULL(c.customer_id, 'UNKNOWN') AS customer_id,
    ISNULL(l.postal_code, -1) AS postal_code,
    ISNULL(p.product_bk, 'UNKNOWN') AS product_bk,
    ISNULL(dd.date_key, 19000101) AS order_date_key,
    ISNULL(ds.date_key, 19000101) AS ship_date_key,
    o.ship_mode,
    o.sales,
    o.quantity,
    o.discount,
    o.profit
FROM silver.orders o
LEFT JOIN silver.customers c ON c.customer_id = o.customer_id
LEFT JOIN silver.locations l ON l.postal_code = o.postal_code
LEFT JOIN silver.products p  ON p.product_bk = o.product_bk
LEFT JOIN gold.vw_dim_date dd ON dd.full_date = o.order_date
LEFT JOIN gold.vw_dim_date ds ON ds.full_date = o.ship_date;
GO

IF OBJECT_ID('gold.vw_executive_kpi_summary', 'V') IS NOT NULL DROP VIEW gold.vw_executive_kpi_summary;
GO
CREATE VIEW gold.vw_executive_kpi_summary AS
SELECT 
    d.[year] AS order_year,
    d.[quarter] AS order_quarter,
    l.state,
    p.category,
    COUNT(DISTINCT f.order_id) AS total_orders,
    SUM(f.sales) AS gross_sales,
    SUM(f.quantity) AS total_quantity,
    SUM(f.profit) AS net_profit,
    ROUND((SUM(f.profit) / NULLIF(SUM(f.sales), 0)) * 100, 2) AS profit_margin_pct,
    CASE 
        WHEN SUM(f.profit) < 0 THEN 'Loss Maker'
        WHEN (SUM(f.profit) / NULLIF(SUM(f.sales), 0)) < 0.10 THEN 'Thin Margin'
        ELSE 'Healthy Margin'
    END AS financial_status
FROM gold.fact_orders f
JOIN gold.dim_date d ON f.order_date_key = d.date_key
JOIN gold.dim_location l ON f.location_key = l.location_key
JOIN gold.dim_product p ON f.product_key = p.product_key
GROUP BY d.[year], d.[quarter], l.state, p.category;
GO
