CREATE TABLE customers AS
SELECT customerid, TRIM(INITCAP(surname)) AS surname,
       TRIM(geography) AS geography, TRIM(gender) AS gender, age
FROM raw_churn;

CREATE TABLE accounts AS
SELECT customerid, creditscore, tenure, balance, numofproducts,
       hascrcard::boolean AS has_card, estimatedsalary
FROM raw_churn;

CREATE TABLE activity AS
SELECT customerid, isactivemember::boolean AS is_active, exited::boolean AS churned
FROM raw_churn;

ALTER TABLE customers ADD PRIMARY KEY (customerid);
ALTER TABLE accounts  ADD PRIMARY KEY (customerid);
ALTER TABLE activity  ADD PRIMARY KEY (customerid);


-- 1. Rows aur unique customers
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT customerid) AS unique_customers FROM raw_churn;

-- 2. Nulls
SELECT COUNT(*) FILTER (WHERE creditscore IS NULL) AS null_credit,
       COUNT(*) FILTER (WHERE age IS NULL) AS null_age,
       COUNT(*) FILTER (WHERE balance IS NULL) AS null_balance
FROM raw_churn;

-- 3. Categories
SELECT geography, COUNT(*) FROM customers GROUP BY 1;
SELECT gender, COUNT(*) FROM customers GROUP BY 1;

-- 4. Value ranges
SELECT MIN(age), MAX(age), MIN(creditscore), MAX(creditscore), MIN(tenure), MAX(tenure)
FROM raw_churn;


CREATE OR REPLACE VIEW customer_360 AS
SELECT c.customerid, c.geography, c.gender, c.age,
       a.creditscore, a.tenure, a.balance, a.numofproducts, a.has_card, a.estimatedsalary,
       v.is_active, v.churned
FROM customers c
JOIN accounts a USING (customerid)
JOIN activity v USING (customerid);


SELECT COUNT(*) FROM customer_360;

SELECT COUNT(*) AS total_customers,
       SUM(churned::int) AS churned_customers,
       ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
FROM customer_360;


WITH banded AS (
  SELECT *,
    CASE WHEN tenure <= 2 THEN '0-2 yrs'
         WHEN tenure <= 5 THEN '3-5 yrs'
         WHEN tenure <= 8 THEN '6-8 yrs'
         ELSE '9-10 yrs' END AS tenure_band
  FROM customer_360
)
SELECT tenure_band, COUNT(*) AS customers,
       ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
FROM banded
GROUP BY tenure_band
ORDER BY MIN(tenure);


SELECT numofproducts, COUNT(*) AS customers,
       ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
FROM customer_360
GROUP BY numofproducts
ORDER BY numofproducts;


SELECT is_active, COUNT(*) AS customers,
       ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
FROM customer_360
GROUP BY is_active;

SELECT geography, COUNT(*) AS customers,
       ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
FROM customer_360
GROUP BY geography
ORDER BY churn_rate_pct DESC;

SELECT CASE WHEN age < 30 THEN '<30'
            WHEN age < 40 THEN '30-39'
            WHEN age < 50 THEN '40-49'
            WHEN age < 60 THEN '50-59'
            ELSE '60+' END AS age_group,
       COUNT(*) AS customers,
       ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
FROM customer_360
GROUP BY 1
ORDER BY MIN(age);

WITH seg AS (
  SELECT geography, numofproducts,
         COUNT(*) AS customers,
         ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
  FROM customer_360
  GROUP BY geography, numofproducts
)
SELECT geography, numofproducts, customers, churn_rate_pct,
       RANK() OVER (PARTITION BY geography ORDER BY churn_rate_pct DESC) AS risk_rank,
       ROUND(churn_rate_pct - AVG(churn_rate_pct) OVER (PARTITION BY geography), 1) AS vs_geo_avg
FROM seg
ORDER BY geography, risk_rank;

SELECT geography, is_active, numofproducts,
       COUNT(*) AS customers,
       ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
FROM customer_360
GROUP BY geography, is_active, numofproducts
HAVING COUNT(*) >= 100
ORDER BY churn_rate_pct DESC
LIMIT 10;

CREATE OR REPLACE VIEW customer_scored AS
SELECT *,
  (CASE WHEN age >= 45 THEN 2 WHEN age >= 35 THEN 1 ELSE 0 END)
+ (CASE WHEN numofproducts IN (3,4) THEN 3 WHEN numofproducts = 1 THEN 1 ELSE 0 END)
+ (CASE WHEN NOT is_active THEN 1 ELSE 0 END)
+ (CASE WHEN geography = 'Germany' THEN 1 ELSE 0 END) AS risk_score
FROM customer_360;


CREATE OR REPLACE VIEW customer_risk AS
SELECT *,
  CASE WHEN risk_score >= 4 THEN 'High'
       WHEN risk_score >= 2 THEN 'Medium'
       ELSE 'Low' END AS risk_tier
FROM customer_scored;

SELECT risk_tier, COUNT(*) AS customers, SUM(churned::int) AS churned,
       ROUND(100.0 * AVG(churned::int), 1) AS churn_rate_pct
FROM customer_risk
GROUP BY risk_tier
ORDER BY churn_rate_pct;