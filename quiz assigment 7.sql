
--Assignment Tasks
--Task 1 — Build the Sales Detail Dataset (6 marks)
--Management needs a detailed sales dataset for analysis. Return one row per order item containing:
--order_id and order_date
--customer full name
--store name
--staff full name
--product name
--category name
--brand name
--quantity, list_price, discount
--calculated net_line_revenue

--Include only completed orders (order_status = 4). Sort the result from newest order to oldest.


SELECT 
    o.order_id,
    o.order_date,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    s.store_name,
    CONCAT(st.first_name, ' ', st.last_name) AS staff_name,
    p.product_name,
    cat.category_name,
    b.brand_name,
    oi.quantity,
    oi.list_price,
    oi.discount,
    CAST(oi.quantity * oi.list_price * (1 - oi.discount) AS DECIMAL(10, 2)) AS net_line_revenue
FROM sales.orders o
INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
INNER JOIN sales.customers c ON o.customer_id = c.customer_id
INNER JOIN sales.stores s ON o.store_id = s.store_id
INNER JOIN sales.staffs st ON o.staff_id = st.staff_id
INNER JOIN production.products p ON oi.product_id = p.product_id
INNER JOIN production.categories cat ON p.category_id = cat.category_id
INNER JOIN production.brands b ON p.brand_id = b.brand_id
WHERE o.order_status = 4  
ORDER BY o.order_date DESC, o.order_id DESC; 


--Task 2 — Store Performance Summary (5 marks)
--Create a store-level performance report for completed orders showing:
--store name
--number of distinct orders
--total units sold
--total net revenue
--average order value

SELECT 
    s.store_name,
    COUNT(DISTINCT o.order_id) AS distinct_orders,
    SUM(oi.quantity) AS total_units_sold,
    CAST(SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS DECIMAL(12, 2)) AS total_net_revenue,
    CAST(
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) / NULLIF(COUNT(DISTINCT o.order_id), 0) 
        AS DECIMAL(10, 2)
    ) AS avg_order_value

FROM sales.stores s
INNER JOIN sales.orders o ON s.store_id = o.store_id
INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 4  
GROUP BY s.store_name
ORDER BY total_net_revenue DESC;


--Task 3 — High-Value Customers (5 marks)
--Management wants to identify high-value customers.
--Return customers whose total completed-order spending is greater than the average total spending of customers who have completed orders.


WITH CustomerSpending AS (
    SELECT 
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        COUNT(DISTINCT o.order_id) AS completed_order_count,
        SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS total_spending
    FROM sales.customers c
    INNER JOIN sales.orders o ON c.customer_id = o.customer_id
    INNER JOIN sales.order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 4 
    GROUP BY c.customer_id, c.first_name, c.last_name

	--Task 4 — Inventory Risk Report (5 marks)
--Operations wants to identify inventory risk. Return products where the stock quantity is below 5 in at least one store.

SELECT 
    p.product_name,
    s.store_name,
    st.quantity AS current_quantity,
    cat.category_name,
    b.brand_name
FROM production.stocks st
INNER JOIN production.products p ON st.product_id = p.product_id
INNER JOIN sales.stores s ON st.store_id = s.store_id
INNER JOIN production.categories cat ON p.category_id = cat.category_id
INNER JOIN production.brands b ON p.brand_id = b.brand_id
WHERE st.quantity < 5
ORDER BY 
    CASE WHEN st.quantity = 0 THEN 0 ELSE 1 END, 
    st.quantity ASC,                            
    p.product_name ASC;



--Task 5 — Top Products Within Each Category (6 marks)
--For each product category, identify the top 3 products by total net revenue from completed orders.

WITH RankedProducts AS (
    SELECT 
        cat.category_name,
        p.product_name,
        CAST(SUM(oi.quantity * oi.list_price * (1 - oi.discount)) AS DECIMAL(12, 2)) AS total_net_revenue,
        DENSE_RANK() OVER (
            PARTITION BY cat.category_name 
            ORDER BY SUM(oi.quantity * oi.list_price * (1 - oi.discount)) DESC
        ) AS rank_in_category
    FROM production.categories cat
    INNER JOIN production.products p ON cat.category_id = p.category_id
    INNER JOIN sales.order_items oi ON p.product_id = oi.product_id
    INNER JOIN sales.orders o ON oi.order_id = o.order_id
    WHERE o.order_status = 4  
    GROUP BY cat.category_name, p.product_id, p.product_name
	)

	SELECT 
    category_name,
    product_name,
    total_net_revenue,
    rank_in_category
FROM RankedProducts
WHERE rank_in_category <= 3
ORDER BY category_name ASC, rank_in_category ASC;


--Task 6 — Monthly Sales Trend (6 marks)
--Create a monthly sales trend for completed orders.

WITH monthly_sales AS (
    SELECT
        EXTRACT(YEAR FROM order_date) AS year,
        EXTRACT(MONTH FROM order_date) AS month,
        SUM(net_revenue) AS total_net_revenue
    FROM orders
    WHERE status = 'completed'
    GROUP BY
        EXTRACT(YEAR FROM order_date),
        EXTRACT(MONTH FROM order_date)
)
SELECT
    year,
    month,
    total_net_revenue,
    LAG(total_net_revenue) OVER (
        ORDER BY year, month
    ) AS previous_month_revenue,
    total_net_revenue - LAG(total_net_revenue) OVER (
        ORDER BY year, month
    ) AS revenue_change
FROM monthly_sales
ORDER BY
    year ASC,
    month ASC;


--	Task 7 — Reusable Reporting View (4 marks)
--Create a view named sales.vw_customer_sales_summary that returns one row per customer and includes:
--customer_id
--customer full name
--total number of completed orders
--total units purchased
--total net revenue
--most recent completed order date

CREATE OR REPLACE VIEW sales.vw_customer_sales_summary AS
SELECT 
    c.customer_id,
    TRIM(CONCAT(c.first_name, ' ', c.last_name)) AS customer_full_name,
    COUNT(DISTINCT o.order_id) AS total_completed_orders,
    COALESCE(SUM(oi.quantity), 0) AS total_units_purchased,
    COALESCE(SUM(oi.quantity * oi.unit_price * (1 - COALESCE(oi.discount, 0))), 0) AS total_net_revenue,
    MAX(o.order_date) AS most_recent_completed_order_date
FROM 
    sales.customers c
LEFT JOIN 
    sales.orders o 
    ON c.customer_id = o.customer_id 
    AND LOWER(o.order_status) = 'completed'
LEFT JOIN 
    sales.order_items oi 
    ON o.order_id = oi.order_id
GROUP BY 
    c.customer_id,
    c.first_name,
    c.last_name;

--Task 8 — Safe Data Modification (4 marks)
--A customer with customer_id = 1 has requested that their phone number be changed to '(999) 555-0101'.

--Write SQL that performs this update inside an explicit transaction. Include a validation query after 
--the UPDATE and show how the change can be rolled back during testing so the assessment database is not permanently changed.

BEGIN TRANSACTION; 
UPDATE sales.customers
SET phone = '(999) 555-0101'
WHERE customer_id = 1;
SELECT 
    customer_id, 
    first_name, 
    last_name, 
    phone
FROM sales.customers
WHERE customer_id = 1;

ROLLBACK;
SELECT 
    customer_id, 
    first_name, 
    last_name, 
    phone
FROM sales.customers
WHERE customer_id = 1;

--Task 9 — Store Sales Procedure (6 marks)
--Create a stored procedure named sales.usp_store_sales_report with these input parameters:
--@store_id
--@start_date
--@end_date

CREATE OR ALTER PROCEDURE sales.usp_store_sales_report
    @store_id   INT,
    @start_date DATE,
    @end_date   DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @start_date > @end_date
    BEGIN
        THROW 50001, 'Invalid date range: @start_date cannot be later than @end_date.', 1;
        RETURN;
    END
    SELECT 
        p.product_name,
        SUM(oi.quantity) AS total_units_sold,
        SUM(oi.quantity * oi.unit_price * (1 - COALESCE(oi.discount, 0))) AS total_net_revenue
    FROM 
        sales.orders o
    INNER JOIN 
        sales.order_items oi 
        ON o.order_id = oi.order_id
    INNER JOIN 
        production.products p 
        ON oi.product_id = p.product_id
    WHERE 
        o.store_id = @store_id
        AND LOWER(o.order_status) = 'completed'
        AND o.order_date >= @start_date
        AND o.order_date <= @end_date
    GROUP BY 
        p.product_name
    ORDER BY 
        total_net_revenue DESC;
END;

--Task 10 — Management Insight Query (3 marks)
--Write one additional SQL query that you believe would provide useful insight to BikeStores management using at least three tables.

SELECT 
    b.brand_name,
    c.category_name,
    COUNT(DISTINCT oi.order_id) AS orders_count,
    SUM(oi.quantity) AS total_units_sold,
    SUM(oi.quantity * oi.unit_price * (1 - COALESCE(oi.discount, 0))) AS total_net_revenue
FROM 
    production.products p
INNER JOIN 
    production.brands b ON p.brand_id = b.brand_id
INNER JOIN 
    production.categories c ON p.category_id = c.category_id
INNER JOIN 
    sales.order_items oi ON p.product_id = oi.product_id
INNER JOIN 
    sales.orders o ON oi.order_id = o.order_id
WHERE 
    LOWER(o.order_status) = 'completed'
GROUP BY 
    b.brand_name,
    c.category_name
ORDER BY 
    total_net_revenue DESC;


