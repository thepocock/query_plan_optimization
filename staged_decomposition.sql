/*
    Query Decomposition Case Study
    ------------------------------
    Anonymized reconstruction of a historical SQL Server optimization rewrite.

    Production database, table, column, client, supplier, and business identifiers
    have been replaced with generic names. This file preserves the optimization
    pattern rather than the original business implementation.

    Pattern demonstrated:
      1. Constrain large source domains early.
      2. Materialize smaller intermediate relations.
      3. Pre-aggregate expensive measures independently.
      4. Assemble the final analytical relation from bounded stages.

    The historical source used global temp tables during experimentation.
    Local temp tables are used here for safer portfolio presentation.
*/

USE [AnalyticsWarehouse];

------------------------------------------------------------
-- Program / client scope
------------------------------------------------------------
SELECT
      pm.CLIENT_NAME_STD
    , pm.CLIENT_NAME_SOURCE
    , pm.PROGRAM_MAP_ID
    , pm.PROGRAM_NAME_ID
    , pm.PROGRAM_NAME
    , pm.VERTICAL_NAME
    , pm.INDUSTRY_NAME
    , p.CLIENT_ID
    , p.SOURCE_SYSTEM
INTO #program
FROM dbo.program_mapping AS pm
INNER JOIN dbo.program AS p
    ON p.PROGRAM_MAP_ID = pm.PROGRAM_MAP_ID;


------------------------------------------------------------
-- Request distributions limited to participating programs
------------------------------------------------------------
SELECT
      rd.REQUEST_ID
    , rd.CLIENT_ID
    , rd.DISTRIBUTION_DATE
    , rd.DECLINE_DATE
    , rd.SUPPLIER_ID
    , rd.REQUEST_DISTRIBUTION_ID
    , rd.SOURCE_SYSTEM
    , rd.DECLINE_REASON_MAP_ID
INTO #request_distribution
FROM dbo.request_distribution AS rd
WHERE EXISTS
(
    SELECT 1
    FROM dbo.program AS p
    WHERE p.CLIENT_ID = rd.CLIENT_ID
      AND p.SOURCE_SYSTEM = rd.SOURCE_SYSTEM
);


------------------------------------------------------------
-- Requests limited to the already-constrained distribution set
------------------------------------------------------------
SELECT
      r.SOURCE_SYSTEM
    , r.CLIENT_ID
    , r.BUSINESS_UNIT_CODE
    , r.CLOSE_DATE
    , r.POSITIONS_REQUESTED
    , r.REQUEST_ID
    , r.PREIDENTIFIED_FLAG
    , r.PAYROLL_SERVICE_FLAG
    , r.LABOR_CATEGORY
    , r.VENDOR_MANAGER
    , r.REQUEST_REASON_FLAG
    , r.SOLUTION_TYPE
    , r.SOURCE_TYPE
    , r.JOB_TITLE_MAP_ID
    , r.STATUS_MAP_ID
    , r.WORK_LOCATION_MAP_ID
    , r.WORK_COUNTRY_MAP_ID
    , r.REQUEST_TYPE_FLAG
    , r.RECRUITING_TYPE_FLAG
    , r.REQUEST_SOURCE_FLAG
    , r.NON_EMPLOYEE_CLASS_FLAG
    , r.ASSIGNMENT_TYPE_FLAG
    , r.OPTIMIZED_POSITION_FLAG
    , r.WORKER_TYPE_FLAG
    , r.CONTRACT_REQUEST_TYPE_FLAG
    , r.NAMED_POSTING_FLAG
    , r.CURRENCY_CODE
INTO #request
FROM dbo.request AS r
WHERE EXISTS
(
    SELECT 1
    FROM #request_distribution AS rd
    WHERE rd.SOURCE_SYSTEM = r.SOURCE_SYSTEM
      AND rd.CLIENT_ID = r.CLIENT_ID
      AND rd.REQUEST_ID = r.REQUEST_ID
)
AND EXISTS
(
    SELECT 1
    FROM dbo.work_location_country_mapping AS wc
    WHERE wc.WORK_COUNTRY_MAP_ID = r.WORK_COUNTRY_MAP_ID
);


------------------------------------------------------------
-- Business-unit lookup reduced to rows used by #request
------------------------------------------------------------
SELECT
      bu.BUSINESS_UNIT_NAME
    , bu.BUSINESS_UNIT_GROUP
    , bu.SOURCE_SYSTEM
    , bu.CLIENT_ID
    , bu.BUSINESS_UNIT_CODE
INTO #business_unit
FROM dbo.business_unit AS bu
WHERE EXISTS
(
    SELECT 1
    FROM #request AS r
    WHERE r.SOURCE_SYSTEM = bu.SOURCE_SYSTEM
      AND r.CLIENT_ID = bu.CLIENT_ID
      AND r.BUSINESS_UNIT_CODE = bu.BUSINESS_UNIT_CODE
);


------------------------------------------------------------
-- Job-title lookup reduced to rows used by #request
------------------------------------------------------------
SELECT
      jt.JOB_TITLE_STD
    , jt.JOB_TITLE_SOURCE
    , jt.LABOR_CATEGORY_STD
    , jt.JOB_TITLE_MAP_ID
INTO #job_title
FROM dbo.job_title_mapping AS jt
WHERE EXISTS
(
    SELECT 1
    FROM #request AS r
    WHERE r.JOB_TITLE_MAP_ID = jt.JOB_TITLE_MAP_ID
);


------------------------------------------------------------
-- Status lookup reduced to rows used by #request
------------------------------------------------------------
SELECT
      rs.STATUS_NAME
    , rs.STATUS_MAP_ID
INTO #request_status
FROM dbo.request_status_mapping AS rs
WHERE EXISTS
(
    SELECT 1
    FROM #request AS r
    WHERE r.STATUS_MAP_ID = rs.STATUS_MAP_ID
);


------------------------------------------------------------
-- Supplier lookup reduced to suppliers present in distributions
------------------------------------------------------------
SELECT
      sm.SUPPLIER_RECOGNITION
    , sm.SUPPLIER_DIVISION
    , sm.SUPPLIER_PARENT
    , sm.SUPPLIER_PARENT_DIVISION
    , sm.SUPPLIER_MAP_ID
    , sm.SUPPLIER_NAME_ID
    , sm.SUPPLIER_NAME_STD
    , sm.SUPPLIER_NAME_SOURCE
    , s.SOURCE_SYSTEM
    , s.CLIENT_ID
    , s.SUPPLIER_ID
INTO #supplier
FROM dbo.supplier AS s
INNER JOIN dbo.supplier_mapping AS sm
    ON sm.SUPPLIER_MAP_ID = s.SUPPLIER_MAP_ID
WHERE EXISTS
(
    SELECT 1
    FROM #request_distribution AS rd
    WHERE rd.SOURCE_SYSTEM = s.SOURCE_SYSTEM
      AND rd.CLIENT_ID = s.CLIENT_ID
      AND rd.SUPPLIER_ID = s.SUPPLIER_ID
);


------------------------------------------------------------
-- Decline-reason lookup reduced to mapped values in use
------------------------------------------------------------
SELECT
      dr.DECLINE_REASON
    , dr.DECLINE_REASON_MAP_ID
INTO #decline_reason
FROM dbo.decline_reason_mapping AS dr
WHERE EXISTS
(
    SELECT 1
    FROM #request_distribution AS rd
    WHERE rd.DECLINE_REASON_MAP_ID = dr.DECLINE_REASON_MAP_ID
);


------------------------------------------------------------
-- Pre-aggregate all request distributions
------------------------------------------------------------
SELECT
      rd.SOURCE_SYSTEM
    , rd.CLIENT_ID
    , rd.REQUEST_ID
    , COUNT(*) AS DISTRIBUTION_COUNT
INTO #distribution_count
FROM dbo.request_distribution AS rd
WHERE EXISTS
(
    SELECT 1
    FROM #request AS r
    WHERE r.SOURCE_SYSTEM = rd.SOURCE_SYSTEM
      AND r.CLIENT_ID = rd.CLIENT_ID
      AND r.REQUEST_ID = rd.REQUEST_ID
)
GROUP BY
      rd.SOURCE_SYSTEM
    , rd.CLIENT_ID
    , rd.REQUEST_ID;


------------------------------------------------------------
-- Materialize distinct mapped supplier distributions
------------------------------------------------------------
SELECT DISTINCT
      rd.SOURCE_SYSTEM
    , rd.REQUEST_ID
    , rd.CLIENT_ID
    , sm.SUPPLIER_NAME_STD
INTO #mapped_distribution
FROM dbo.request_distribution AS rd
INNER JOIN dbo.supplier AS s
    ON s.SOURCE_SYSTEM = rd.SOURCE_SYSTEM
   AND s.CLIENT_ID = rd.CLIENT_ID
   AND s.SUPPLIER_ID = rd.SUPPLIER_ID
INNER JOIN dbo.supplier_mapping AS sm
    ON sm.SUPPLIER_MAP_ID = s.SUPPLIER_MAP_ID;


SELECT
      md.SOURCE_SYSTEM
    , md.CLIENT_ID
    , md.REQUEST_ID
    , COUNT(*) AS MAPPED_DISTRIBUTION_COUNT
INTO #mapped_distribution_count
FROM #mapped_distribution AS md
GROUP BY
      md.SOURCE_SYSTEM
    , md.CLIENT_ID
    , md.REQUEST_ID;


------------------------------------------------------------
-- Normalize requested rates once, independently
------------------------------------------------------------
SELECT
      r.SOURCE_SYSTEM
    , r.REQUEST_ID
    , r.CLIENT_ID
    , CASE
        WHEN r.CLIENT_ID IN
        (
            'CLIENT_01', 'CLIENT_02', 'CLIENT_03', 'CLIENT_04',
            'CLIENT_05', 'CLIENT_06', 'CLIENT_07', 'CLIENT_08',
            'CLIENT_09', 'CLIENT_10', 'CLIENT_11', 'CLIENT_12',
            'CLIENT_13', 'CLIENT_14'
        )
        THEN COALESCE(r.MAX_HOURLY_RATE, r.MAX_DAILY_RATE / 8.0)
        ELSE COALESCE(r.TEMPLATE_MAX_HOURLY_RATE, r.TEMPLATE_MAX_DAILY_RATE / 8.0)
      END AS MAX_REQUESTED_HOURLY_RATE
INTO #request_rate
FROM dbo.request_rate_source AS r;


------------------------------------------------------------
-- Pre-aggregate submission / candidate funnel measures
------------------------------------------------------------
SELECT
      c.SOURCE_SYSTEM
    , c.REQUEST_ID
    , c.SUPPLIER_ID
    , c.CLIENT_ID
    , rr.MAX_REQUESTED_HOURLY_RATE
    , CASE WHEN COUNT(*) > 0 THEN 1 ELSE 0 END AS RESPONDED
    , COUNT(*) AS SUBMITTED
    , SUM(CASE WHEN c.SHORTLIST_DATE IS NULL THEN 0 ELSE 1 END) AS SHORTLISTED
    , SUM(CASE WHEN c.INTERVIEW_DATE IS NULL THEN 0 ELSE 1 END) AS INTERVIEWED
    , SUM(CASE WHEN c.WITHDRAW_DATE IS NULL THEN 0 ELSE 1 END) AS WITHDRAWN
    , SUM(CASE WHEN c.REJECT_DATE IS NULL THEN 0 ELSE 1 END) AS REJECTED
    , AVG
      (
        CASE
          WHEN rr.MAX_REQUESTED_HOURLY_RATE > 1
           AND COALESCE(c.SUBMIT_HOURLY_RATE, c.SUBMIT_DAILY_RATE / 8.0) > 1
          THEN COALESCE(c.SUBMIT_HOURLY_RATE, c.SUBMIT_DAILY_RATE / 8.0)
               / rr.MAX_REQUESTED_HOURLY_RATE
        END
      ) AS AVG_SUBMITTED_RATE_RATIO
INTO #submission_metrics
FROM dbo.candidate_submission AS c
LEFT JOIN #request_rate AS rr
    ON rr.SOURCE_SYSTEM = c.SOURCE_SYSTEM
   AND rr.CLIENT_ID = c.CLIENT_ID
   AND rr.REQUEST_ID = c.REQUEST_ID
GROUP BY
      c.SOURCE_SYSTEM
    , c.REQUEST_ID
    , c.SUPPLIER_ID
    , c.CLIENT_ID
    , rr.MAX_REQUESTED_HOURLY_RATE;


------------------------------------------------------------
-- Pre-aggregate order evaluation measures
------------------------------------------------------------
SELECT
      oe.SOURCE_SYSTEM
    , oe.CLIENT_ID
    , oe.ORDER_ID
    , AVG(oe.EVALUATION_RATING) AS AVG_EVALUATION_RATING
INTO #order_evaluation
FROM dbo.order_evaluation AS oe
GROUP BY
      oe.SOURCE_SYSTEM
    , oe.CLIENT_ID
    , oe.ORDER_ID;


------------------------------------------------------------
-- Pre-aggregate order / hire measures
------------------------------------------------------------
SELECT
      o.SOURCE_SYSTEM
    , o.REQUEST_ID
    , o.CLIENT_ID
    , o.SUPPLIER_ID
    , COUNT(*) AS HIRES
    , SUM
      (
        CASE
          WHEN rr.MAX_REQUESTED_HOURLY_RATE > 1
           AND o.REGULAR_HOURLY_RATE > 1
           AND rr.MAX_REQUESTED_HOURLY_RATE >= o.REGULAR_HOURLY_RATE
          THEN 1 ELSE 0
        END
      ) AS COMPLIANT_HIRES
    , SUM
      (
        CASE
          WHEN rr.MAX_REQUESTED_HOURLY_RATE > 1
           AND o.REGULAR_HOURLY_RATE > 1
          THEN 1 ELSE 0
        END
      ) AS HIRES_WITH_COMPARABLE_RATES
    , SUM(CASE WHEN cr.CLOSE_REASON LIKE '%false%start%' THEN 1 ELSE 0 END) AS FALSE_STARTS
    , SUM(CASE WHEN o.END_DATE > GETDATE() THEN 1 ELSE 0 END) AS ACTIVE_HIRES
    , SUM(CASE WHEN oe.AVG_EVALUATION_RATING IS NOT NULL THEN 1 ELSE 0 END) AS ORDER_EVALUATIONS
    , SUM(oe.AVG_EVALUATION_RATING) AS ORDER_EVALUATION_TOTAL
    , SUM(CASE WHEN cr.POSITIVE_NEGATIVE_FLAG = '0' THEN 1 ELSE 0 END) AS NEGATIVE_ENDS
    , SUM(CASE WHEN o.ACTIVATION_DATE IS NOT NULL THEN 1 ELSE 0 END) AS ACTIVATED_WORK_ORDERS
INTO #hire_metrics
FROM dbo.work_order AS o
LEFT JOIN dbo.order_close_reason_mapping AS cr
    ON cr.CLOSE_REASON_MAP_ID = o.CLOSE_REASON_MAP_ID
LEFT JOIN #request_rate AS rr
    ON rr.SOURCE_SYSTEM = o.SOURCE_SYSTEM
   AND rr.CLIENT_ID = o.CLIENT_ID
   AND rr.REQUEST_ID = o.REQUEST_ID
LEFT JOIN #order_evaluation AS oe
    ON oe.SOURCE_SYSTEM = o.SOURCE_SYSTEM
   AND oe.CLIENT_ID = o.CLIENT_ID
   AND oe.ORDER_ID = o.ORDER_ID
WHERE o.ACTIVATION_DATE IS NOT NULL
GROUP BY
      o.SOURCE_SYSTEM
    , o.CLIENT_ID
    , o.REQUEST_ID
    , o.SUPPLIER_ID;


------------------------------------------------------------
-- Location dimensions constrained to rows used by #request
------------------------------------------------------------
SELECT
      wl.CITY_NAME
    , wl.STATE_PROVINCE_CODE
    , wl.POSTAL_CODE
    , wl.WORK_LOCATION_MAP_ID
INTO #work_location
FROM dbo.work_location_mapping AS wl
WHERE EXISTS
(
    SELECT 1
    FROM #request AS r
    WHERE r.WORK_LOCATION_MAP_ID = wl.WORK_LOCATION_MAP_ID
);


SELECT
      wc.COUNTRY_NAME
    , wc.REGION_NAME
    , wc.WORK_COUNTRY_MAP_ID
INTO #work_country
FROM dbo.work_location_country_mapping AS wc
WHERE EXISTS
(
    SELECT 1
    FROM #request AS r
    WHERE r.WORK_COUNTRY_MAP_ID = wc.WORK_COUNTRY_MAP_ID
);


/*
    Optional stage-specific indexes can be introduced after row counts and
    join patterns are known. The point is not "index every temp table"; it is
    to make each materialized stage independently observable and tunable.

    Example:

    CREATE INDEX IX_request_distribution_keys
        ON #request_distribution (SOURCE_SYSTEM, CLIENT_ID, REQUEST_ID);

    CREATE INDEX IX_submission_metrics_keys
        ON #submission_metrics (SOURCE_SYSTEM, CLIENT_ID, REQUEST_ID, SUPPLIER_ID);

    CREATE INDEX IX_hire_metrics_keys
        ON #hire_metrics (SOURCE_SYSTEM, CLIENT_ID, REQUEST_ID, SUPPLIER_ID);
*/
