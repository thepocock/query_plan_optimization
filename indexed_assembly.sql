/*
    Indexed Assembly Example
    ------------------------
    Anonymized reconstruction based on surviving historical working notes.

    This is a portfolio example of the next step after decomposition:
    index bounded intermediate relations, join them in controlled stages,
    and preserve the keys needed by subsequent stages.

    It is representative of the optimization strategy, not a claim to be
    the exact final production query.
*/

------------------------------------------------------------
-- Index the first bounded relations
------------------------------------------------------------
CREATE INDEX IX_request_distribution_client
    ON #request_distribution (CLIENT_ID);

CREATE INDEX IX_request_distribution_source
    ON #request_distribution (SOURCE_SYSTEM);

CREATE INDEX IX_program_client
    ON #program (CLIENT_ID);

CREATE INDEX IX_program_source
    ON #program (SOURCE_SYSTEM);


------------------------------------------------------------
-- Stage 1: program + request distribution
------------------------------------------------------------
SELECT
      p.CLIENT_NAME_SOURCE
    , p.CLIENT_NAME_STD
    , p.PROGRAM_MAP_ID
    , p.INDUSTRY_NAME
    , p.PROGRAM_NAME
    , p.PROGRAM_NAME_ID
    , p.VERTICAL_NAME
    , rd.CLIENT_ID
    , rd.DECLINE_DATE
    , rd.DISTRIBUTION_DATE
    , rd.SOURCE_SYSTEM
    , rd.SUPPLIER_ID
    , rd.REQUEST_DISTRIBUTION_ID
    , rd.REQUEST_ID
INTO #stage_01
FROM #program AS p
INNER JOIN #request_distribution AS rd
    ON rd.CLIENT_ID = p.CLIENT_ID
   AND rd.SOURCE_SYSTEM = p.SOURCE_SYSTEM;


CREATE INDEX IX_stage_01_request
    ON #stage_01 (SOURCE_SYSTEM, CLIENT_ID, REQUEST_ID);


------------------------------------------------------------
-- Index request relation before joining it
------------------------------------------------------------
CREATE INDEX IX_request_source
    ON #request (SOURCE_SYSTEM);

CREATE INDEX IX_request_request
    ON #request (REQUEST_ID);

CREATE INDEX IX_request_client
    ON #request (CLIENT_ID);


------------------------------------------------------------
-- Stage 2: add request attributes while preserving join keys
------------------------------------------------------------
SELECT
      s1.CLIENT_NAME_SOURCE
    , s1.CLIENT_NAME_STD
    , s1.PROGRAM_MAP_ID
    , s1.INDUSTRY_NAME
    , s1.PROGRAM_NAME
    , s1.PROGRAM_NAME_ID
    , s1.VERTICAL_NAME
    , s1.DECLINE_DATE
    , s1.DISTRIBUTION_DATE
    , s1.SUPPLIER_ID
    , s1.REQUEST_DISTRIBUTION_ID
    , r.SOURCE_SYSTEM
    , r.CLIENT_ID
    , r.REQUEST_ID
    , r.BUSINESS_UNIT_CODE
    , r.ASSIGNMENT_TYPE_FLAG
    , r.CLOSE_DATE
    , r.CONTRACT_REQUEST_TYPE_FLAG
    , r.CURRENCY_CODE
    , r.LABOR_CATEGORY
    , r.NAMED_POSTING_FLAG
    , r.POSITIONS_REQUESTED
    , r.NON_EMPLOYEE_CLASS_FLAG
    , r.PREIDENTIFIED_FLAG
    , r.PAYROLL_SERVICE_FLAG
    , r.RECRUITING_TYPE_FLAG
    , r.REQUEST_REASON_FLAG
    , r.REQUEST_SOURCE_FLAG
    , r.REQUEST_TYPE_FLAG
    , r.SOLUTION_TYPE
    , r.SOURCE_TYPE
    , r.OPTIMIZED_POSITION_FLAG
    , r.VENDOR_MANAGER
    , r.WORKER_TYPE_FLAG
INTO #stage_02
FROM #stage_01 AS s1
INNER JOIN #request AS r
    ON r.SOURCE_SYSTEM = s1.SOURCE_SYSTEM
   AND r.CLIENT_ID = s1.CLIENT_ID
   AND r.REQUEST_ID = s1.REQUEST_ID;


CREATE INDEX IX_stage_02_business_unit
    ON #stage_02 (SOURCE_SYSTEM, CLIENT_ID, BUSINESS_UNIT_CODE);


------------------------------------------------------------
-- Stage 3: add business-unit attributes
------------------------------------------------------------
CREATE INDEX IX_business_unit_source
    ON #business_unit (SOURCE_SYSTEM);

CREATE INDEX IX_business_unit_code
    ON #business_unit (BUSINESS_UNIT_CODE);

CREATE INDEX IX_business_unit_client
    ON #business_unit (CLIENT_ID);


SELECT
      s2.*
    , bu.BUSINESS_UNIT_NAME
    , bu.BUSINESS_UNIT_GROUP
INTO #stage_03
FROM #stage_02 AS s2
LEFT JOIN #business_unit AS bu
    ON bu.SOURCE_SYSTEM = s2.SOURCE_SYSTEM
   AND bu.CLIENT_ID = s2.CLIENT_ID
   AND bu.BUSINESS_UNIT_CODE = s2.BUSINESS_UNIT_CODE;


/*
    Subsequent stages would follow the same pattern:

      #stage_03
          -> job title
          -> request status
          -> supplier
          -> decline reason
          -> distribution aggregates
          -> submission aggregates
          -> hire/order aggregates
          -> location dimensions
          -> final analytical relation

    The optimization principle is the important artifact:

      large monolithic expression
            ->
      constrained materialized relations
            ->
      stage-specific statistics / indexes
            ->
      independently optimizable joins
            ->
      controlled final assembly
*/
