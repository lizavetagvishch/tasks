CREATE TABLE mart.sales_mart (
    sales_key SERIAL PRIMARY KEY,
    order_date DATE NOT NULL,
    ship_date DATE NOT NULL,
    order_id TEXT NOT NULL,
    customer_key INTEGER NOT NULL,
    customer_id TEXT NOT NULL,
    customer_name TEXT NOT NULL,
    segment TEXT NOT NULL,
    product_key INTEGER NOT NULL,
    product_id TEXT NOT NULL,
    product_name TEXT NOT NULL,
    category TEXT NOT NULL,
    sub_category TEXT NOT NULL,
    region TEXT NOT NULL,
    country TEXT NOT NULL,
    city TEXT NOT NULL,
    state TEXT NOT NULL,
    postal_code INTEGER,
    sales NUMERIC(10,2) NOT NULL,
    quantity INTEGER NOT NULL,
    discount NUMERIC(4,2) NOT NULL,
    profit NUMERIC(10,2) NOT NULL,
    ship_mode TEXT NOT NULL,
    days_to_ship INTEGER NOT NULL,
    month_key INTEGER NOT NULL,
    quarter_key INTEGER NOT NULL,
    year_key INTEGER NOT NULL
);

CREATE INDEX idx_sales_mart_date ON mart.sales_mart(order_date);
CREATE INDEX idx_sales_mart_customer ON mart.sales_mart(customer_key);
CREATE INDEX idx_sales_mart_product ON mart.sales_mart(product_key);
CREATE INDEX idx_sales_mart_region ON mart.sales_mart(region);

CREATE TABLE mart.customer_mart (
    customer_key INTEGER PRIMARY KEY,
    customer_id TEXT NOT NULL,
    customer_name TEXT NOT NULL,
    segment TEXT NOT NULL,
    first_order_date DATE NOT NULL,
    last_order_date DATE NOT NULL,
    total_orders INTEGER NOT NULL,
    total_sales NUMERIC(12,2) NOT NULL,
    avg_order_value NUMERIC(10,2) NOT NULL,
    favorite_category TEXT NOT NULL,
    favorite_sub_category TEXT NOT NULL,
    days_since_last_order INTEGER,
    customer_rank INTEGER
);

CREATE INDEX idx_customer_mart_segment ON mart.customer_mart(segment);

CREATE TABLE mart.product_mart (
    product_key INTEGER PRIMARY KEY,
    product_id TEXT NOT NULL,
    product_name TEXT NOT NULL,
    category TEXT NOT NULL,
    sub_category TEXT NOT NULL,
    total_sales NUMERIC(12,2) NOT NULL,
    total_quantity INTEGER NOT NULL,
    total_profit NUMERIC(12,2) NOT NULL,
    avg_discount NUMERIC(4,2) NOT NULL,
    sales_rank INTEGER,
    profit_rank INTEGER,
    popularity_rank INTEGER
);

CREATE INDEX idx_product_mart_category ON mart.product_mart(category);
CREATE INDEX idx_product_mart_sub_category ON mart.product_mart(sub_category);

CREATE TABLE mart.sales_daily_aggregated (
    date_key DATE PRIMARY KEY,
    total_sales NUMERIC(12,2) NOT NULL,
    total_profit NUMERIC(12,2) NOT NULL,
    total_quantity INTEGER NOT NULL,
    avg_order_value NUMERIC(10,2) NOT NULL,
    unique_customers INTEGER NOT NULL,
    unique_products INTEGER NOT NULL
);

CREATE TABLE mart.sales_by_category (
    category_key SERIAL PRIMARY KEY,
    category TEXT NOT NULL,
    sub_category TEXT NOT NULL,
    month_key INTEGER NOT NULL,
    year_key INTEGER NOT NULL,
    total_sales NUMERIC(12,2) NOT NULL,
    total_profit NUMERIC(12,2) NOT NULL,
    sales_growth_pct NUMERIC(5,2),
    profit_margin_pct NUMERIC(5,2),
    UNIQUE (category, sub_category, month_key, year_key)
);

CREATE OR REPLACE PROCEDURE mart.refresh_sales_mart()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE mart.sales_mart;
    
    INSERT INTO mart.sales_mart (
        order_date, ship_date, order_id, customer_key, customer_id, 
        customer_name, segment, product_key, product_id, product_name,
        category, sub_category, region, country, city, state, postal_code,
        sales, quantity, discount, profit, ship_mode, days_to_ship,
        month_key, quarter_key, year_key
    )
    SELECT 
        o.order_date,
        o.ship_date,
        o.order_id,
        o.customer_key,
        c.customer_id,
        c.customer_name,
        c.segment,
        p.product_key,
        p.product_id,
        p.product_name,
        cat.category_name,
        cat.sub_category_name,
        r.region_name,
        g.country,
        g.city,
        g.state,
        g.postal_code,
        oi.sales,
        oi.quantity,
        oi.discount,
        oi.profit,
        sm.ship_mode_name,
        (o.ship_date - o.order_date) AS days_to_ship,
        EXTRACT(YEAR FROM o.order_date) * 100 + EXTRACT(MONTH FROM o.order_date) AS month_key,
        EXTRACT(YEAR FROM o.order_date) * 10 + EXTRACT(QUARTER FROM o.order_date) AS quarter_key,
        EXTRACT(YEAR FROM o.order_date) AS year_key
    FROM core.order_items oi
    JOIN core.orders o ON oi.order_key = o.order_key
    JOIN core.customers c ON o.customer_key = c.customer_key
    JOIN core.products p ON oi.product_key = p.product_key
    JOIN core.categories cat ON p.sub_category_id = cat.category_id
    JOIN core.geography g ON o.geo_key = g.geo_key
    JOIN core.regions r ON g.region_id = r.region_id
    JOIN core.ship_modes sm ON o.ship_mode_id = sm.ship_mode_id;
    
    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE mart.refresh_customer_mart()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE mart.customer_mart;
    
    INSERT INTO mart.customer_mart (
        customer_key, customer_id, customer_name, segment,
        first_order_date, last_order_date, total_orders,
        total_sales, avg_order_value, favorite_category,
        favorite_sub_category, days_since_last_order, customer_rank
    )
    WITH customer_stats AS (
        SELECT
            c.customer_key,
            c.customer_id,
            c.customer_name,
            c.segment,
            MIN(s.order_date) AS first_order_date,
            MAX(s.order_date) AS last_order_date,
            COUNT(DISTINCT s.order_id) AS total_orders,
            SUM(s.sales) AS total_sales,
            SUM(s.sales) / COUNT(DISTINCT s.order_id) AS avg_order_value
        FROM mart.sales_mart s
        JOIN core.customers c ON s.customer_key = c.customer_key
        GROUP BY c.customer_key, c.customer_id, c.customer_name, c.segment
    ),
    favorite_categories AS (
        SELECT
            customer_key,
            category AS favorite_category,
            sub_category AS favorite_sub_category,
            ROW_NUMBER() OVER (PARTITION BY customer_key ORDER BY COUNT(*) DESC) AS rn
        FROM mart.sales_mart
        GROUP BY customer_key, category, sub_category
    )
    SELECT
        cs.*,
        fc.favorite_category,
        fc.favorite_sub_category,
        CURRENT_DATE - cs.last_order_date AS days_since_last_order,
        RANK() OVER (ORDER BY cs.total_sales DESC) AS customer_rank
    FROM customer_stats cs
    JOIN favorite_categories fc ON cs.customer_key = fc.customer_key AND fc.rn = 1;
    
    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE mart.refresh_product_mart()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE mart.product_mart;
    
    INSERT INTO mart.product_mart (
        product_key, product_id, product_name, category, sub_category,
        total_sales, total_quantity, total_profit, avg_discount,
        sales_rank, profit_rank, popularity_rank
    )
    WITH product_stats AS (
        SELECT
            p.product_key,
            p.product_id,
            p.product_name,
            cat.category_name AS category,
            cat.sub_category_name AS sub_category,
            SUM(s.sales) AS total_sales,
            SUM(s.quantity) AS total_quantity,
            SUM(s.profit) AS total_profit,
            AVG(s.discount) AS avg_discount,
            COUNT(DISTINCT s.order_id) AS order_count
        FROM mart.sales_mart s
        JOIN core.products p ON s.product_key = p.product_key
        JOIN core.categories cat ON p.sub_category_id = cat.category_id
        GROUP BY p.product_key, p.product_id, p.product_name, cat.category_name, cat.sub_category_name
    ),
    ranked_products AS (
        SELECT
            product_key,
            product_id,
            product_name,
            category,
            sub_category,
            total_sales,
            total_quantity,
            total_profit,
            avg_discount,
            RANK() OVER (ORDER BY total_sales DESC) AS sales_rank,
            RANK() OVER (ORDER BY total_profit DESC) AS profit_rank,
            RANK() OVER (ORDER BY order_count DESC) AS popularity_rank
        FROM product_stats
    )
    SELECT
        product_key,
        product_id,
        product_name,
        category,
        sub_category,
        total_sales,
        total_quantity,
        total_profit,
        avg_discount,
        sales_rank,
        profit_rank,
        popularity_rank
    FROM ranked_products;
    
    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE mart.refresh_daily_sales()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE mart.sales_daily_aggregated;
    
    INSERT INTO mart.sales_daily_aggregated (
        date_key, total_sales, total_profit, total_quantity,
        avg_order_value, unique_customers, unique_products
    )
    SELECT
        s.order_date AS date_key,
        SUM(s.sales) AS total_sales,
        SUM(s.profit) AS total_profit,
        SUM(s.quantity) AS total_quantity,
        SUM(s.sales) / COUNT(DISTINCT s.order_id) AS avg_order_value,
        COUNT(DISTINCT s.customer_key) AS unique_customers,
        COUNT(DISTINCT s.product_key) AS unique_products
    FROM mart.sales_mart s
    GROUP BY s.order_date;
    
    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE mart.refresh_category_sales()
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE TABLE mart.sales_by_category;
    
    WITH current_stats AS (
        SELECT
            s.category,
            s.sub_category,
            EXTRACT(YEAR FROM s.order_date) * 100 + EXTRACT(MONTH FROM s.order_date) AS month_key,
            EXTRACT(YEAR FROM s.order_date) AS year_key,
            SUM(s.sales) AS current_sales,
            SUM(s.profit) AS current_profit
        FROM mart.sales_mart s
        GROUP BY s.category, s.sub_category, 
                 EXTRACT(YEAR FROM s.order_date), EXTRACT(MONTH FROM s.order_date)
    ),
    previous_stats AS (
        SELECT
            s.category,
            s.sub_category,
            EXTRACT(YEAR FROM s.order_date) * 100 + EXTRACT(MONTH FROM s.order_date) AS month_key,
            EXTRACT(YEAR FROM s.order_date) AS year_key,
            SUM(s.sales) AS previous_sales
        FROM mart.sales_mart s
        GROUP BY s.category, s.sub_category, 
                 EXTRACT(YEAR FROM s.order_date), EXTRACT(MONTH FROM s.order_date)
    )
    INSERT INTO mart.sales_by_category (
        category, sub_category, month_key, year_key,
        total_sales, total_profit, sales_growth_pct, profit_margin_pct
    )
    SELECT
        cs.category,
        cs.sub_category,
        cs.month_key,
        cs.year_key,
        cs.current_sales AS total_sales,
        cs.current_profit AS total_profit,
        CASE 
            WHEN ps.previous_sales > 0 THEN 
                (cs.current_sales - ps.previous_sales) / ps.previous_sales * 100
            ELSE NULL
        END AS sales_growth_pct,
        CASE 
            WHEN cs.current_sales > 0 THEN 
                (cs.current_profit / cs.current_sales) * 100
            ELSE NULL
        END AS profit_margin_pct
    FROM current_stats cs
    LEFT JOIN previous_stats ps ON cs.category = ps.category
                              AND cs.sub_category = ps.sub_category
                              AND cs.month_key = ps.month_key + 1
                              AND cs.year_key = ps.year_key;
    
    COMMIT;
END;
$$;

CREATE OR REPLACE PROCEDURE mart.refresh_all_marts()
LANGUAGE plpgsql
AS $$
BEGIN
    CALL mart.refresh_sales_mart();
    
    CALL mart.refresh_customer_mart();
    CALL mart.refresh_product_mart();
    CALL mart.refresh_daily_sales();
    CALL mart.refresh_category_sales();
    
    REFRESH MATERIALIZED VIEW mart.mv_sales_monthly;
    
    COMMIT;
END;
$$;

CALL mart.refresh_all_marts();