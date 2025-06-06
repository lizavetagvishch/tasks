CREATE SCHEMA IF NOT EXISTS stage;
CREATE TABLE stage.superstore_raw (
    row_id INTEGER,
    order_id TEXT,
    order_date DATE,
    ship_date DATE,
    ship_mode TEXT,
    customer_id TEXT,
    customer_name TEXT,
    segment TEXT,
    country TEXT,
    city TEXT,
    state TEXT,
    postal_code INTEGER,
    region TEXT,
    product_id TEXT,
    category TEXT,
    sub_category TEXT,
    product_name TEXT,
    sales NUMERIC(10, 2),
    quantity INTEGER,
    discount NUMERIC(4, 2),
    profit NUMERIC(10, 2)
);