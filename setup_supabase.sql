-- ============================================================
-- VALYX SALES DASHBOARD - SUPABASE DATABASE SETUP SCRIPT
-- ============================================================

-- Drop tables in order of dependencies if they exist
DROP FUNCTION IF EXISTS public.get_sales_dashboard(DATE);
DROP TABLE IF EXISTS public.orders CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;
DROP TABLE IF EXISTS public.products CASCADE;
DROP TABLE IF EXISTS public.destinations CASCADE;
DROP TABLE IF EXISTS public.wallet_summary CASCADE;

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. USERS TABLE
CREATE TABLE public.users (
    user_id INT PRIMARY KEY,
    name VARCHAR(255),
    country_code VARCHAR(50),
    mobile VARCHAR(50),
    user_role INT,
    created_datetime TIMESTAMP WITH TIME ZONE
);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public select users" ON public.users FOR SELECT USING (true);

-- 2. PRODUCTS TABLE
CREATE TABLE public.products (
    prod_id INT PRIMARY KEY,
    add_on_id VARCHAR(255),
    data_limit INT,
    sim_mode INT,
    fup_limit INT,
    operator_id INT,
    additional_note TEXT,
    amount NUMERIC(10,2),
    product_name VARCHAR(255),
    post_fup_speed VARCHAR(50),
    validity INT,
    coverage_destinations TEXT,
    allocated_destinations TEXT
);

ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public select products" ON public.products FOR SELECT USING (true);

-- 3. DESTINATIONS TABLE
CREATE TABLE public.destinations (
    destination_id VARCHAR(50) PRIMARY KEY,
    destination_type INT,
    destination_name VARCHAR(255),
    flag_path TEXT,
    included_destinations TEXT,
    is_active BOOLEAN
);

ALTER TABLE public.destinations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public select destinations" ON public.destinations FOR SELECT USING (true);

-- 4. ORDERS TABLE
CREATE TABLE public.orders (
    order_no INT PRIMARY KEY,
    user_id INT REFERENCES public.users(user_id),
    product_id INT REFERENCES public.products(prod_id),
    amount NUMERIC(10,2),
    discount_amount NUMERIC(10,2),
    created_by INT REFERENCES public.users(user_id),
    order_date_time TIMESTAMP WITH TIME ZONE
);

ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow public select orders" ON public.orders FOR SELECT USING (true);


-- 5. DEFINE RPC FUNCTION get_sales_dashboard
CREATE OR REPLACE FUNCTION public.get_sales_dashboard(report_data DATE)
RETURNS TABLE (
    daily_metrics jsonb,
    month_metrics jsonb,
    kpi_metrics jsonb,
    sales_rep_metrics jsonb,
    destinations jsonb,
    wallet_metrics jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    first_day_of_month DATE;
    prev_month_start DATE;
    prev_month_same_day DATE;
    prev_month_end DATE;
BEGIN
    -- Derive target dates based on input report_data
    first_day_of_month := date_trunc('month', report_data)::date;
    prev_month_start := date_trunc('month', report_data - INTERVAL '1 month')::date;
    prev_month_same_day := (report_data - INTERVAL '1 month')::date;
    prev_month_end := (date_trunc('month', report_data) - INTERVAL '1 day')::date;

    RETURN QUERY
    SELECT 
        -- daily_metrics: Daily orders/revenue count for the selected month of report_data
        (
            SELECT COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'order_date', to_char(d, 'YYYY-MM-DD'),
                        'orders', COALESCE(ord.orders, 0),
                        'revenue', COALESCE(ord.revenue, 0.00)
                    )
                    ORDER BY d
                ),
                '[]'::jsonb
            )
            FROM generate_series(first_day_of_month, (first_day_of_month + INTERVAL '1 month' - INTERVAL '1 day')::date, INTERVAL '1 day') d
            LEFT JOIN (
                SELECT order_date_time::date AS o_date, COUNT(*) AS orders, SUM(amount - discount_amount) AS revenue
                FROM public.orders
                GROUP BY order_date_time::date
            ) ord ON ord.o_date = d::date
        ) AS daily_metrics,

        -- month_metrics: Monthly order trend aggregates across all available data
        (
            SELECT COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'month', sub.m,
                        'year', sub.y,
                        'orders', sub.orders,
                        'revenue', sub.revenue
                    )
                    ORDER BY sub.y, sub.m
                ),
                '[]'::jsonb
            )
            FROM (
                SELECT 
                    EXTRACT(MONTH FROM order_date_time)::int AS m,
                    EXTRACT(YEAR FROM order_date_time)::int AS y,
                    COUNT(*) AS orders,
                    SUM(amount - discount_amount) AS revenue
                FROM public.orders
                GROUP BY EXTRACT(YEAR FROM order_date_time)::int, EXTRACT(MONTH FROM order_date_time)::int
            ) sub
        ) AS month_metrics,

        -- kpi_metrics: Main high-level summary cards (Today, Month-To-Date, Prev Month Same Day, and Prev Month Total)
        (
            SELECT jsonb_build_array(
                jsonb_build_object(
                    'today_sales', COALESCE(SUM(CASE WHEN order_date_time::date = report_data THEN 1 ELSE 0 END), 0),
                    'today_revenue', COALESCE(SUM(CASE WHEN order_date_time::date = report_data THEN amount - discount_amount ELSE 0.00 END), 0.00),
                    'mtd_sales', COALESCE(SUM(CASE WHEN order_date_time::date >= first_day_of_month AND order_date_time::date <= report_data THEN 1 ELSE 0 END), 0),
                    'mtd_revenue', COALESCE(SUM(CASE WHEN order_date_time::date >= first_day_of_month AND order_date_time::date <= report_data THEN amount - discount_amount ELSE 0.00 END), 0.00),
                    'prev_month_same_day_sales', COALESCE(SUM(CASE WHEN order_date_time::date >= prev_month_start AND order_date_time::date <= prev_month_same_day THEN 1 ELSE 0 END), 0),
                    'prev_month_same_day_revenue', COALESCE(SUM(CASE WHEN order_date_time::date >= prev_month_start AND order_date_time::date <= prev_month_same_day THEN amount - discount_amount ELSE 0.00 END), 0.00),
                    'prev_month_sales', COALESCE(SUM(CASE WHEN order_date_time::date >= prev_month_start AND order_date_time::date <= prev_month_end THEN 1 ELSE 0 END), 0),
                    'prev_month_revenue', COALESCE(SUM(CASE WHEN order_date_time::date >= prev_month_start AND order_date_time::date <= prev_month_end THEN amount - discount_amount ELSE 0.00 END), 0.00)
                )
            )
            FROM public.orders
        ) AS kpi_metrics,

        -- sales_rep_metrics: Daily Leaderboard aggregated by agent (user_role = 2)
        (
            WITH rep_today AS (
                SELECT created_by, COUNT(*) as tdy_sales, SUM(amount - discount_amount) as tdy_revenue
                FROM public.orders
                WHERE order_date_time::date = report_data
                GROUP BY created_by
            ),
            rep_mtd AS (
                SELECT created_by, COUNT(*) as mtd_sales, SUM(amount - discount_amount) as mtd_revenue
                FROM public.orders
                WHERE order_date_time::date >= first_day_of_month AND order_date_time::date <= report_data
                GROUP BY created_by
            ),
            rep_prev AS (
                SELECT created_by, COUNT(*) as pv_month
                FROM public.orders
                WHERE order_date_time::date >= prev_month_start AND order_date_time::date <= prev_month_end
                GROUP BY created_by
            )
            SELECT COALESCE(jsonb_agg(jsonb_build_object(
                'sales_rep', COALESCE(NULLIF(TRIM(u.name), ''), 'Rep #' || u.user_id::text),
                'tdy_sales', COALESCE(rt.tdy_sales, 0),
                'tdy_revenue', COALESCE(rt.tdy_revenue, 0.00),
                'mtd_sales', COALESCE(rm.mtd_sales, 0),
                'mtd_revenue', COALESCE(rm.mtd_revenue, 0.00)
            ) ORDER BY COALESCE(rm.mtd_sales, 0) DESC), '[]'::jsonb)
            FROM public.users u
            LEFT JOIN rep_today rt ON u.user_id = rt.created_by
            LEFT JOIN rep_mtd rm ON u.user_id = rm.created_by
            LEFT JOIN rep_prev rp ON u.user_id = rp.created_by
            WHERE u.user_role = 2
              AND (rt.tdy_sales IS NOT NULL OR rm.mtd_sales IS NOT NULL OR rp.pv_month IS NOT NULL)
        ) AS sales_rep_metrics,

        -- destinations: Bookings mapped dynamic from actual products.coverageDestinations
        (
            SELECT COALESCE(jsonb_agg(jsonb_build_object('destination', sub.destination_name, 'bookings', sub.bookings)), '[]'::jsonb)
            FROM (
                SELECT d.destination_name, COUNT(*) AS bookings
                FROM public.orders o
                JOIN public.products p ON o.product_id = p.prod_id
                CROSS JOIN LATERAL regexp_split_to_table(p.coverage_destinations, ',') AS dest_id
                JOIN public.destinations d ON TRIM(dest_id) = d.destination_id
                WHERE o.order_date_time::date <= report_data
                GROUP BY d.destination_name
                ORDER BY bookings DESC
                LIMIT 10
            ) sub
        ) AS destinations,

        -- wallet_metrics: Explicitly documented zero-derived values (real wallet data is unavailable in CSV)
        (
            SELECT jsonb_build_object(
                'account_balance', 0.00,
                'pending_payouts', 0.00,
                'total_withdrawn', 0.00
            )
        ) AS wallet_metrics;
END;
$$;

-- Grant execute permission to anon and authenticated users
GRANT EXECUTE ON FUNCTION public.get_sales_dashboard(DATE) TO anon;
GRANT EXECUTE ON FUNCTION public.get_sales_dashboard(DATE) TO authenticated;

-- Notify schema reload
NOTIFY pgrst, 'reload schema';
