
-- =====================================================
-- ==  MULTI-TABLE E-COMMERCE EUROPEAN FASHION ==
-- =====================================================

-- =====================================================
-- 1) DATABASE CREATION
-- =====================================================

DROP DATABASE IF EXISTS "01_portfolio_ecommerce";

CREATE DATABASE "01_portfolio_ecommerce"
	WITH
	OWNER = postgres
	ENCODING = 'UTF8'
	LC_COLLATE = 'Spanish_Chile.1252'
	LC_CTYPE = 'Spanish_Chile.1252'
	LOCALE_PROVIDER = 'libc'
	TABLESPACE = pg_default
	CONNECTION LIMIT = -1
	IS_TEMPLATE = False;

-- =====================================================
-- 2) TABLES
-- =====================================================

DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS channels CASCADE;
DROP TABLE IF EXISTS campaigns CASCADE;
DROP TABLE IF EXISTS sales CASCADE;
DROP TABLE IF EXISTS salesitems CASCADE;
DROP TABLE IF EXISTS stock CASCADE;

CREATE TABLE customers (
	customer_id INT PRIMARY KEY,
	country TEXT,
	age_range TEXT,
	signup_date DATE
);

CREATE TABLE products (
	product_id INT PRIMARY KEY,
	product_name TEXT,
	category TEXT,
	brand TEXT,
	color TEXT,
	size TEXT,
	catalog_price NUMERIC(5,2),
	cost_price NUMERIC(5,2),
	gender TEXT
);

CREATE TABLE channels (
	channel TEXT PRIMARY KEY,
	description TEXT
);

CREATE TABLE campaigns (
	campaign_id INT PRIMARY KEY,
	campaign_name TEXT,
	start_date DATE,
	end_date DATE,
	channel TEXT,
	discount_type TEXT,
	discount_value TEXT
);

CREATE TABLE sales (
	sale_id INT PRIMARY KEY,
	channel TEXT,
	discounted BOOLEAN,
	total_amount NUMERIC (5,2),
	sale_date DATE,
	customer_id INT REFERENCES customers(customer_id),
	country TEXT
);

CREATE TABLE salesitems (
	item_id INT PRIMARY KEY,
	sale_id INT REFERENCES sales(sale_id),
	product_id INT REFERENCES products(product_id),
	quantity INT, 
	original_price NUMERIC(5,2),
	unit_price NUMERIC(5,2),
	discount_applied NUMERIC(5,2),
	discount_percent TEXT,
	discounted BOOLEAN,
	item_total NUMERIC(5,2),
	sale_date DATE,
	channel TEXT REFERENCES channels(channel),
	channel_campaigns TEXT
);

CREATE TABLE stock (
    country TEXT,
    product_id INT REFERENCES products(product_id),
    stock_quantity INT,
    PRIMARY KEY (country, product_id)
);

-- =====================================================
-- 3) CSV LOADING (INTERFACE -> IMPORT DATA)
-- =====================================================

-- =====================================================
-- 4) DATA CLEANING AND MANIPULATION
-- =====================================================

-- 4A) == PERCENTAGE CONVERSION (%) ==

ALTER TABLE campaigns 
ADD COLUMN discount_value_clean NUMERIC(4,2);

UPDATE campaigns 
SET discount_value_clean = 
    CAST(REPLACE(discount_value, '%', '') AS NUMERIC);

ALTER TABLE campaigns 
DROP COLUMN discount_value;

ALTER TABLE campaigns 
RENAME COLUMN discount_value_clean TO discount_value;

ALTER TABLE salesitems 
ADD COLUMN discount_percent_clean NUMERIC(4,2);

UPDATE salesitems 
SET discount_percent_clean = 
    CAST(REPLACE(discount_percent, '%', '') AS NUMERIC);

ALTER TABLE salesitems 
DROP COLUMN discount_percent;

ALTER TABLE salesitems 
RENAME COLUMN discount_percent_clean TO discount_percent;

-- 4B) == DUPLICATE CHECK ==

SELECT customer_id, COUNT(*)
FROM customers
GROUP BY customer_id
HAVING COUNT(*) > 1;

SELECT product_id, COUNT(*)
FROM products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- 4C) == RELATIONSHIP VALIDATION ==

SELECT si.sale_id
FROM salesitems si
LEFT JOIN sales s ON si.sale_id = s.sale_id
WHERE s.sale_id IS NULL;

SELECT si.product_id
FROM salesitems si
LEFT JOIN products p ON si.product_id = p.product_id
WHERE p.product_id IS NULL;

-- 4D) == SALES VALUE VERIFICATION ==

SELECT
    s.sale_id,
    s.total_amount AS sale_total,
    SUM(si.item_total) AS items_total,
    ROUND(s.total_amount - SUM(si.item_total), 2) AS diff
FROM sales s
JOIN salesitems si ON s.sale_id = si.sale_id
GROUP BY s.sale_id, s.total_amount
HAVING ROUND(s.total_amount - SUM(si.item_total), 2) <> 0;

-- =====================================================
-- 5) QUERIES
-- =====================================================

-- 5A) == REVENUE BY CHANNEL ==

SELECT
    channel,
    COUNT(*) AS total_sales,
    ROUND(SUM(total_amount), 2) AS revenue
FROM sales
GROUP BY channel
ORDER BY revenue DESC;

-- 5B) == TOP 10 PRODUCTS BY REVENUE ==

SELECT
    p.product_name,
    p.category,
    SUM(si.quantity) AS units_sold,
    ROUND(SUM(si.item_total), 2) AS revenue
FROM salesitems si
JOIN products p ON si.product_id = p.product_id
GROUP BY p.product_name, p.category
ORDER BY revenue DESC
LIMIT 10;

-- 5C) == REVENUE BY COUNTRY ==

SELECT
    country,
    COUNT(*) AS total_orders,
    ROUND(SUM(total_amount), 2) AS revenue
FROM sales
GROUP BY country
ORDER BY revenue DESC;

-- 5D) == DISCOUNT VS. NO DISCOUNT ==

SELECT
    discounted,
    COUNT(*) AS total_items,
    ROUND(SUM(item_total), 2) AS revenue,
    ROUND(AVG(discount_percent), 2) AS avg_discount_pct
FROM salesitems
GROUP BY discounted;

-- 5E) == REVENUE BY AGE GROUP ==

SELECT
    c.age_range,
    COUNT(DISTINCT s.sale_id) AS orders,
    ROUND(SUM(s.total_amount), 2) AS revenue
FROM sales s
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.age_range
ORDER BY c.age_range;

-- =====================================================
-- 6) ANALYSIS TABLE FOR PYTHON
-- =====================================================

CREATE OR REPLACE VIEW sales_analysis AS
SELECT
    s.sale_id,
    s.sale_date,
    s.channel AS sale_channel,
    s.discounted AS sale_discounted,
    s.total_amount,
    s.country AS sale_country,
    s.customer_id,
    c.age_range,
    c.signup_date,
    si.item_id,
    si.product_id,
    si.quantity,
    si.original_price,
    si.unit_price,
    si.discount_applied,
    si.discount_percent,
    si.discounted AS item_discounted,
    si.item_total,
    si.channel_campaigns,
    p.product_name,
    p.category,
    p.brand,
    p.color,
    p.size,
    p.catalog_price,
    p.cost_price,
    p.gender,
    cam.campaign_id,
    cam.campaign_name,
    cam.start_date AS campaign_start_date,
    cam.end_date AS campaign_end_date,
    cam.channel AS campaign_channel,
    cam.discount_type,
    cam.discount_value

FROM sales s
JOIN customers c
    ON s.customer_id = c.customer_id
JOIN salesitems si
    ON s.sale_id = si.sale_id
JOIN products p
    ON si.product_id = p.product_id
LEFT JOIN campaigns cam
    ON si.channel_campaigns = cam.channel;