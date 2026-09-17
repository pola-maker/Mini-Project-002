# 📊 Mini Project 002 — Superstore Data Warehouse & ETL Pipeline

A SQL Server data engineering project that transforms raw **Central Superstore** sales data into a structured, validated, and analytics-ready data warehouse.

The project demonstrates a complete ETL workflow using a **Medallion Architecture**:

**Staging → Bronze → Silver → Gold**

The goal is to practice real-world SQL Server data engineering concepts including data ingestion, data cleaning, validation, deduplication, dimensional modeling, and data quality management.

---

## 📌 Project Overview

The project uses the **Central Superstore** dataset containing sales transactions, customers, products, locations, shipping information, discounts, sales, and profits.

The raw CSV data is first loaded into a staging area and then processed through multiple warehouse layers.

### Data Flow

```text
Central_Superstore.csv
        │
        ▼
   STAGING LAYER
        │
        ▼
    BRONZE LAYER
   Raw Data Storage
        │
        ▼
    SILVER LAYER
 Data Cleaning & Validation
        │
        ▼
     GOLD LAYER
Dimensional Data Warehouse
```

---

## 🏗️ Architecture

### 1. Staging Layer

The staging layer provides the initial landing area for the raw CSV data.

The source data is loaded using SQL Server `BULK INSERT`.

```sql
BULK INSERT staging_superstore
FROM '.../Central_Superstore.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    FORMAT = 'CSV',
    FIELDQUOTE = '"',
    CODEPAGE = '65001'
);
```

The staging table initially stores the incoming fields as text so that the raw source data can be ingested before transformation.

---

### 2. Bronze Layer 🥉

The Bronze layer stores the raw ingested data.

It preserves the source values while adding metadata such as:

* `bronze_id`
* `_ingested_at`
* `_source_batch`

The pipeline also prevents duplicate records from being inserted into the Bronze layer.

This layer acts as the historical/raw data foundation of the warehouse.

---

### 3. Silver Layer 🥈

The Silver layer is responsible for **data cleansing, transformation, and validation**.

The project performs operations such as:

* Trimming unnecessary whitespace
* Converting strings into appropriate data types
* Converting dates into `DATE`
* Converting sales and profit into decimal values
* Converting quantities into integers
* Validating discounts
* Detecting missing values
* Detecting invalid values
* Checking referential integrity
* Identifying duplicate/latest records
* Detecting statistical outliers

For example, the project uses `TRY_CAST()` to safely convert raw values:

```sql
TRY_CAST(order_date AS DATE)
TRY_CAST(sales AS DECIMAL(12,4))
TRY_CAST(quantity AS INT)
TRY_CAST(discount AS DECIMAL(6,4))
TRY_CAST(profit AS DECIMAL(12,4))
```

### Data Quality Flags

The Silver layer tracks several data-quality conditions:

```text
has_missing_value
has_invalid_value
has_outlier_value
```

Outliers in sales and profit are identified using the **Interquartile Range (IQR)** method.

```text
Lower Bound = Q1 - 1.5 × IQR
Upper Bound = Q3 + 1.5 × IQR
```

---

## 🥇 Gold Layer

The Gold layer provides the analytics-ready warehouse model.

The project uses dimensional modeling to separate descriptive entities from transactional facts.

Examples of dimensional entities include:

* Customers
* Products
* Locations
* Dates

The project also uses surrogate keys and an `UNKNOWN` member to handle unmatched dimension records.

Example:

```text
gold.dim_customer
```

The Gold layer is designed to make the cleaned data easier to query for reporting and analytics.

---

## 📂 Repository Structure

```text
Mini-Project-002/
│
├── .gitignore
│
├── Central_Superstore.csv
│
├── Central_Superstore.xlsx
│
└── Mini-Project-002.sql
```

### Files

| File                      | Description                                          |
| ------------------------- | ---------------------------------------------------- |
| `Central_Superstore.csv`  | Raw Superstore dataset used as the main source       |
| `Central_Superstore.xlsx` | Excel version of the dataset                         |
| `Mini-Project-002.sql`    | Complete SQL Server ETL and warehouse implementation |
| `.gitignore`              | Git files and folders excluded from version control  |

The CSV currently contains approximately **2,324 lines / 517 KB** in the repository.

---

## 🛠️ Technologies Used

* **Microsoft SQL Server**
* **T-SQL**
* **SQL Server Management Studio (SSMS)**
* **Git & GitHub**
* CSV
* Microsoft Excel

---

## 🧠 SQL Concepts Demonstrated

This project applies several important SQL Server concepts:

### Data Ingestion

* `BULK INSERT`
* CSV handling
* File encoding
* Staging tables

### Data Transformation

* `CAST()`
* `TRY_CAST()`
* `LTRIM()`
* `RTRIM()`
* `NULLIF()`
* `CONCAT()`

### Data Quality

* Missing-value detection
* Invalid-value detection
* Referential integrity checks
* Validation rules
* Outlier detection

### Advanced SQL

* Common Table Expressions (`CTEs`)
* `ROW_NUMBER()`
* `MERGE`
* Window functions
* `PERCENTILE_CONT()`
* `CASE`
* `EXCEPT`
* `CROSS JOIN`

### Data Warehouse Concepts

* Medallion Architecture
* Fact and dimension modeling
* Surrogate keys
* Business keys
* Unknown dimension members
* ETL/ELT pipelines
* Data quality flags

---

## 🔍 Data Quality Rules

The pipeline checks several types of data-quality problems.

### Missing Values

Important fields are checked for missing values, including:

* Customer ID
* Order Date
* Sales
* Quantity

### Invalid Values

Examples of invalid records include:

* Invalid dates
* Invalid sales values
* Negative sales
* Zero or negative quantities
* Discounts outside the `0–1` range
* Customers that do not exist in the customer dimension
* Locations that do not exist in the location dimension
* Products that do not exist in the product dimension

### Outliers

Sales and profit outliers are detected using the IQR statistical method.

This allows unusual transactions to be flagged without automatically deleting them.

---

## 🚀 How to Run the Project

### 1. Clone the Repository

```bash
git clone https://github.com/pola-maker/Mini-Project-002.git
```

```bash
cd Mini-Project-002
```

### 2. Open SQL Server Management Studio

Open the following file:

```text
Mini-Project-002.sql
```

### 3. Configure the CSV Path

The SQL script currently contains a local Windows path for `BULK INSERT`.

Update:

```sql
FROM 'D:\Mini-project-002\Central_Superstore.csv'
```

to the location of the CSV file on your computer.

For example:

```sql
FROM 'C:\YourPath\Mini-Project-002\Central_Superstore.csv'
```

### 4. Execute the SQL Script

Run the script in SQL Server Management Studio.

The script will create and populate the different warehouse layers.

---

## 📈 Example Analytical Questions

Once the Gold layer is populated, the warehouse can be used to answer questions such as:

* What are the total sales by year?
* Which products generate the highest profit?
* Which customers generate the most revenue?
* What are the most profitable product categories?
* Which regions generate the highest sales?
* What shipping modes are most frequently used?
* Which transactions contain data-quality issues?
* Which products have unusually high or low sales?
* How does discount affect profitability?

---

## 🎯 Learning Objectives

This project was created to practice the transition from basic SQL querying to a more realistic **data engineering workflow**.

The main learning objectives are:

1. Understand ETL pipeline architecture.
2. Work with raw CSV data in SQL Server.
3. Build staging and warehouse layers.
4. Clean and transform raw data.
5. Implement data-quality checks.
6. Detect duplicate records.
7. Detect statistical outliers.
8. Build dimensional tables.
9. Apply SQL Server window functions.
10. Create an analytics-ready data warehouse.

---

## 🔄 Project Pipeline

```text
                 RAW DATA
                    │
                    ▼
        ┌──────────────────────┐
        │   STAGING LAYER      │
        │ Raw CSV Ingestion    │
        └──────────┬───────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │   BRONZE LAYER       │
        │ Raw Historical Data  │
        └──────────┬───────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │    SILVER LAYER      │
        │ Cleaning             │
        │ Transformation       │
        │ Validation           │
        │ Deduplication        │
        │ Outlier Detection    │
        └──────────┬───────────┘
                   │
                   ▼
        ┌──────────────────────┐
        │     GOLD LAYER       │
        │ Dimensions           │
        │ Facts                │
        │ Analytics Model      │
        └──────────┬───────────┘
                   │
                   ▼
             ANALYTICS
```

---

## 📚 Project Status

**Status:** Completed SQL ETL / Data Warehouse Mini Project

Future improvements could include:

* Adding a dedicated fact table
* Creating additional dimensions
* Adding automated data-quality reports
* Creating SQL views for analytics
* Connecting the Gold layer to Power BI
* Adding KPI dashboards
* Automating the ETL process with SQL Server Agent

---

## 👤 Author

**Pola Maker**

GitHub: [@pola-maker](https://github.com/pola-maker)

---

## ⭐ Repository

[Mini-Project-002](https://github.com/pola-maker/Mini-Project-002)

---

## 📄 License

This project is intended for educational and portfolio purposes.
