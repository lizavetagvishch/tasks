CREATE OR REPLACE PROCEDURE core.load_categories()
LANGUAGE plpgsql
AS $$
BEGIN


    INSERT INTO core.categories (category_name, sub_category_name, last_updated)

    SELECT DISTINCT category, sub_category, CURRENT_TIMESTAMP

    FROM stage.superstore_raw

    WHERE (category, sub_category) NOT IN (

        SELECT category_name, sub_category_name FROM core.categories

    );

    

    COMMIT;

END;
$$;

CREATE OR REPLACE PROCEDURE core.load_customers()
LANGUAGE plpgsql
AS $$
BEGIN


    CREATE TEMP TABLE stage_customers AS

    SELECT 

        customer_id,

        customer_name,

        segment

    FROM stage.superstore_raw

    GROUP BY customer_id, customer_name, segment;

    


    UPDATE core.customers c

    SET 

        valid_to_date = CURRENT_DATE - INTERVAL '1 day',

        current_flag = 'N',

        etl_load_date = CURRENT_TIMESTAMP

    FROM stage_customers sc

    WHERE c.customer_id = sc.customer_id

      AND c.current_flag = 'Y'

      AND (c.customer_name != sc.customer_name OR c.segment != sc.segment);

    


    INSERT INTO core.customers (

        customer_id, customer_name, segment,

        valid_from_date, valid_to_date, current_flag, version_number

    )

    SELECT 

        sc.customer_id,

        sc.customer_name,

        sc.segment,

        CURRENT_DATE,

        NULL,

        'Y',

        COALESCE((SELECT MAX(version_number) FROM core.customers WHERE customer_id = sc.customer_id), 0) + 1

    FROM stage_customers sc

    WHERE NOT EXISTS (

        SELECT 1 FROM core.customers c 

        WHERE c.customer_id = sc.customer_id 

          AND c.current_flag = 'Y'

          AND c.customer_name = sc.customer_name 

          AND c.segment = sc.segment

    );

    


    INSERT INTO core.customers (

        customer_id, customer_name, segment,

        valid_from_date, valid_to_date, current_flag, version_number

    )

    SELECT 

        sc.customer_id,

        sc.customer_name,

        sc.segment,

        CURRENT_DATE,

        NULL,

        'Y',

        1

    FROM stage_customers sc

    WHERE sc.customer_id NOT IN (SELECT customer_id FROM core.customers);

    

    DROP TABLE stage_customers;

    COMMIT;

END;
$$;

CREATE OR REPLACE PROCEDURE core.load_geography()
LANGUAGE plpgsql
AS $$
BEGIN


    CREATE TEMP TABLE stage_geo AS

    SELECT 

        country,

        city,

        state,

        postal_code,

        r.region_id

    FROM stage.superstore_raw st

    JOIN core.regions r ON st.region = r.region_name

    GROUP BY country, city, state, postal_code, r.region_id;

    


    UPDATE core.geography g

    SET 

        valid_to_date = CURRENT_DATE - INTERVAL '1 day',

        current_flag = 'N',

        etl_load_date = CURRENT_TIMESTAMP

    FROM stage_geo sg

    WHERE g.country = sg.country

      AND g.city = sg.city

      AND g.state = sg.state

      AND (g.postal_code = sg.postal_code OR (g.postal_code IS NULL AND sg.postal_code IS NULL))

      AND g.current_flag = 'Y'

      AND g.region_id != sg.region_id;

    


    INSERT INTO core.geography (

        country, city, state, postal_code, region_id,

        valid_from_date, valid_to_date, current_flag, version_number

    )

    SELECT 

        sg.country,

        sg.city,

        sg.state,

        sg.postal_code,

        sg.region_id,

        CURRENT_DATE,

        NULL,

        'Y',

        COALESCE((SELECT MAX(version_number) 

                 FROM core.geography g 

                 WHERE g.country = sg.country

                   AND g.city = sg.city

                   AND g.state = sg.state

                   AND (g.postal_code = sg.postal_code OR (g.postal_code IS NULL AND sg.postal_code IS NULL))), 0) + 1

    FROM stage_geo sg

    WHERE NOT EXISTS (

        SELECT 1 FROM core.geography g

        WHERE g.country = sg.country

          AND g.city = sg.city

          AND g.state = sg.state

          AND (g.postal_code = sg.postal_code OR (g.postal_code IS NULL AND sg.postal_code IS NULL))

          AND g.current_flag = 'Y'

          AND g.region_id = sg.region_id

    );

    


    INSERT INTO core.geography (

        country, city, state, postal_code, region_id,

        valid_from_date, valid_to_date, current_flag, version_number

    )

    SELECT 

        sg.country,

        sg.city,

        sg.state,

        sg.postal_code,

        sg.region_id,

        CURRENT_DATE,

        NULL,

        'Y',

        1

    FROM stage_geo sg

    WHERE NOT EXISTS (

        SELECT 1 FROM core.geography g

        WHERE g.country = sg.country

          AND g.city = sg.city

          AND g.state = sg.state

          AND (g.postal_code = sg.postal_code OR (g.postal_code IS NULL AND sg.postal_code IS NULL))

    );

    

    DROP TABLE stage_geo;

    COMMIT;

END;
$$;

CREATE OR REPLACE PROCEDURE core.load_order_items()
LANGUAGE plpgsql
AS $$
BEGIN


    CREATE TEMP TABLE temp_order_items AS

    SELECT 

        o.order_key,

        p.product_key,

        SUM(st.quantity) as quantity,

        SUM(st.sales) as sales,

        MAX(st.discount) as discount,

        SUM(st.profit) as profit

    FROM stage.superstore_raw st

    JOIN core.orders o ON st.order_id = o.order_id

    JOIN core.products p ON st.product_id = p.product_id AND p.current_flag = 'Y'

    GROUP BY o.order_key, p.product_key;

    


    CREATE INDEX idx_temp_order_items ON temp_order_items(order_key, product_key);

    


    LOCK TABLE core.order_items IN EXCLUSIVE MODE;

    


    DELETE FROM temp_order_items toi

    WHERE EXISTS (

        SELECT 1 FROM core.order_items oi

        WHERE oi.order_key = toi.order_key

          AND oi.product_key = toi.product_key

    );

    


    INSERT INTO core.order_items (

        order_key, product_key, quantity, sales, discount, profit

    )

    SELECT 

        order_key,

        product_key,

        quantity,

        sales,

        discount,

        profit

    FROM temp_order_items;

    

    DROP TABLE temp_order_items;

    COMMIT;

END;
$$;

CREATE OR REPLACE PROCEDURE core.load_orders()
LANGUAGE plpgsql
AS $$
BEGIN


    CREATE TEMP TABLE temp_orders AS

    SELECT 

        st.order_id,

        MAX(st.order_date) as order_date,

        MAX(st.ship_date) as ship_date,

        MAX(st.customer_id) as customer_id,

        MAX(st.ship_mode) as ship_mode,

        MAX(st.country) as country,

        MAX(st.city) as city,

        MAX(st.state) as state,

        MAX(st.postal_code) as postal_code,

        MAX(st.region) as region

    FROM stage.superstore_raw st

    GROUP BY st.order_id;

    


    CREATE INDEX idx_temp_orders_id ON temp_orders(order_id);

    


    LOCK TABLE core.orders IN EXCLUSIVE MODE;

    


    WITH update_data AS (

        SELECT 

            t.order_id,

            t.order_date,

            t.ship_date,

            c.customer_key,

            sm.ship_mode_id,

            g.geo_key

        FROM temp_orders t

        JOIN core.customers c ON t.customer_id = c.customer_id AND c.current_flag = 'Y'

        JOIN core.ship_modes sm ON t.ship_mode = sm.ship_mode_name

        JOIN core.geography g ON t.country = g.country

                            AND t.city = g.city

                            AND t.state = g.state

                            AND (t.postal_code = g.postal_code OR (t.postal_code IS NULL AND g.postal_code IS NULL))

                            AND g.current_flag = 'Y'

        WHERE EXISTS (SELECT 1 FROM core.orders o WHERE o.order_id = t.order_id)

    )

    UPDATE core.orders o

    SET 

        order_date = ud.order_date,

        ship_date = ud.ship_date,

        customer_key = ud.customer_key,

        ship_mode_id = ud.ship_mode_id,

        geo_key = ud.geo_key,

        etl_load_date = CURRENT_TIMESTAMP

    FROM update_data ud

    WHERE o.order_id = ud.order_id;

    


    INSERT INTO core.orders (

        order_id, order_date, ship_date,

        customer_key, ship_mode_id, geo_key

    )

    SELECT 

        t.order_id,

        t.order_date,

        t.ship_date,

        c.customer_key,

        sm.ship_mode_id,

        g.geo_key

    FROM temp_orders t

    JOIN core.customers c ON t.customer_id = c.customer_id AND c.current_flag = 'Y'

    JOIN core.ship_modes sm ON t.ship_mode = sm.ship_mode_name

    JOIN core.geography g ON t.country = g.country

                        AND t.city = g.city

                        AND t.state = g.state

                        AND (t.postal_code = g.postal_code OR (t.postal_code IS NULL AND g.postal_code IS NULL))

                        AND g.current_flag = 'Y'

    WHERE NOT EXISTS (

        SELECT 1 FROM core.orders o WHERE o.order_id = t.order_id

    )

    ON CONFLICT (order_id) DO NOTHING;

    

    DROP TABLE temp_orders;

    COMMIT;

END;
$$;

CREATE OR REPLACE PROCEDURE core.load_products()
LANGUAGE plpgsql
AS $$
DECLARE

    prod_rec RECORD;

    v_current_count INTEGER;

BEGIN


    CREATE TEMP TABLE stage_products AS

    SELECT 

        st.product_id,

        st.product_name,

        c.category_id as sub_category_id

    FROM stage.superstore_raw st

    JOIN core.categories c ON st.category = c.category_name AND st.sub_category = c.sub_category_name

    GROUP BY st.product_id, st.product_name, c.category_id;

    


    CREATE INDEX idx_stage_products_id ON stage_products(product_id);

    

    FOR prod_rec IN SELECT * FROM stage_products

    LOOP


        SELECT COUNT(*) INTO v_current_count

        FROM core.products p

        WHERE p.product_id = prod_rec.product_id

          AND p.current_flag = 'Y'

          AND p.product_name = prod_rec.product_name

          AND p.sub_category_id = prod_rec.sub_category_id;

        


        CONTINUE WHEN v_current_count > 0;

        


        UPDATE core.products p

        SET 

            valid_to_date = CURRENT_DATE - INTERVAL '1 day',

            current_flag = 'N',

            etl_load_date = CURRENT_TIMESTAMP

        WHERE p.product_id = prod_rec.product_id

          AND p.current_flag = 'Y';

        


        INSERT INTO core.products (

            product_id, product_name, sub_category_id,

            valid_from_date, valid_to_date, current_flag, version_number

        )

        SELECT 

            prod_rec.product_id,

            prod_rec.product_name,

            prod_rec.sub_category_id,

            CURRENT_DATE,

            NULL,

            'Y',

            COALESCE(MAX(version_number), 0) + 1

        FROM core.products

        WHERE product_id = prod_rec.product_id;

        


        IF NOT FOUND THEN

            INSERT INTO core.products (

                product_id, product_name, sub_category_id,

                valid_from_date, valid_to_date, current_flag, version_number

            )

            VALUES (

                prod_rec.product_id,

                prod_rec.product_name,

                prod_rec.sub_category_id,

                CURRENT_DATE,

                NULL,

                'Y',

                1

            );

        END IF;

    END LOOP;

    

    DROP TABLE stage_products;

    COMMIT;

END;
$$;

CREATE OR REPLACE PROCEDURE core.load_regions()
LANGUAGE plpgsql
AS $$
BEGIN


    INSERT INTO core.regions (region_name, last_updated)

    SELECT DISTINCT region, CURRENT_TIMESTAMP

    FROM stage.superstore_raw

    WHERE region NOT IN (SELECT region_name FROM core.regions);

    

    COMMIT;

END;
$$;


CREATE OR REPLACE PROCEDURE core.load_ship_modes()
LANGUAGE plpgsql
AS $$
BEGIN


    INSERT INTO core.ship_modes (ship_mode_name, last_updated)

    SELECT DISTINCT ship_mode, CURRENT_TIMESTAMP

    FROM stage.superstore_raw

    WHERE ship_mode NOT IN (SELECT ship_mode_name FROM core.ship_modes);


    UPDATE core.ship_modes sm

    SET 

        ship_mode_name = st.ship_mode,

        last_updated = CURRENT_TIMESTAMP

    FROM stage.superstore_raw st

    WHERE sm.ship_mode_name != st.ship_mode;

    

    COMMIT;

END;
$$;

CREATE OR REPLACE PROCEDURE core.load_core_layer()
LANGUAGE plpgsql
AS $$
BEGIN

    -- Загружаем SCD1 измерения

    CALL core.load_regions();

    CALL core.load_ship_modes();

    CALL core.load_categories();

    

    -- Загружаем SCD2 измерения

    CALL core.load_customers();

    CALL core.load_geography();

    CALL core.load_products();

    

    -- Загружаем факты

    CALL core.load_orders();

    CALL core.load_order_items();

    

    COMMIT;

END;
$$;

