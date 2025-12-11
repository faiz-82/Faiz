WITH test_cases AS (
    SELECT *
    FROM UNNEST([
        STRUCT(
            '97124' AS service_code,
            '11426' AS zip_code,
            '10801' AS specialty_code,
            'CPT4' AS service_type_code,
            '11' AS place_of_service_code,
            'S' AS contract_type_standard,
            15.74 AS allowed_amount
        ),
        STRUCT(
            '97124' AS service_code,
            '21044' AS zip_code,
            'AP' AS specialty_code,
            'CPT4' AS service_type_code,
            '11' AS place_of_service_code,
            'S' AS contract_type_standard,
            145 AS allowed_amount
        ),
        STRUCT(
            '97124' AS service_code,
            '11758' AS zip_code,
            'AP' AS specialty_code,
            'CPT4' AS service_type_code,
            '11' AS place_of_service_code,
            'S' AS contract_type_standard,
            15.74 AS allowed_amount
        )
    ])
),

Standard_zips AS (
    SELECT DISTINCT
        tc.service_code,
        tc.zip_code,
        tc.specialty_code,
        tc.service_type_code,
        tc.place_of_service_code,
        tc.contract_type_standard,
        tc.allowed_amount,
        t1.ZIP_CD,
        t1.RATING_SYSTEM_CD AS TIN_RATING_SYSTEM_CD,
        t1.GEOGRAPHIC_AREA_CD AS tin_GEOGRAPHIC_AREA_CD,
        t3.GEOGRAPHIC_AREA_CD,
        t3.OVERRIDE_RATE_SYSTEM_CD
    FROM test_cases tc
    JOIN `prv_ps_ce_hcb_dev.CET_EPDB_TAX_IDENTIFICATION_NUMBER_ADDRESS_DETAIL_VIEW` t1
      ON t1.ZIP_CD = tc.zip_code
    LEFT JOIN `prv_ps_ce_hcb_dev.CET_EPDB_CONTRACT_PROVIDER_BUSINESS_GROUP_VIEW` t2
      ON t1.provider_identification_nbr = t2.provider_identification_nbr
     AND t1.tax_identification_nbr     = t2.tax_identification_nbr
     AND t1.service_location_nbr       = t2.service_location_nbr
     AND t1.network_id                 = t2.network_id
    LEFT JOIN `prv_ps_ce_hcb_dev.CET_SCSR_RATE_OVERRIDE_VIEW` t3
      ON t1.ZIP_CD          = t3.GEOGRAPHIC_AREA_CD
     AND t1.RATING_SYSTEM_CD = t3.RATE_SYSTEM_CD
    WHERE t2.provider_business_group_nbr IS NULL
      AND (t3.OVERRIDE_RATE_SYSTEM_CD = '' OR t3.OVERRIDE_RATE_SYSTEM_CD IS NULL)
),

rate_results AS (
    SELECT DISTINCT
        sp.service_code,
        sp.zip_code,
        sp.specialty_code,
        sp.service_type_code,
        sp.place_of_service_code,
        sp.contract_type_standard,
        sp.allowed_amount,
        t4.RATE_SYSTEM_CD,
        t4.SERVICE_CD,
        t4.SERVICE_TYPE_CD,
        sp.tin_GEOGRAPHIC_AREA_CD AS GEOGRAPHIC_AREA_CD,
        t4.SPECIALTY_CD,
        t4.SPECIALTY_TYPE_CD,
        CAST(t4.RATE_AMT AS FLOAT64) AS RATE
    FROM Standard_zips sp
    JOIN `prv_ps_ce_hcb_dev.CET_SCSR_RATE_DETAIL_VIEW` t4
      ON t4.RATE_SYSTEM_CD     = sp.TIN_RATING_SYSTEM_CD
     AND t4.GEOGRAPHIC_AREA_CD = sp.tin_GEOGRAPHIC_AREA_CD
    JOIN `prv_ps_ce_hcb_dev.CET_SCSR_DIFFERENTIATION_CRITERIA_VIEW` tsdc
      ON tsdc.differentiation_criteria_id = t4.differentiation_criteria_id
    JOIN `prv_ps_ce_dec_hcb_dev.service_code_master` scm
      ON TRIM(scm.primary_svc_cd) = t4.SERVICE_CD
    WHERE t4.EXTENSION_CD = ''
      AND scm.in_scope_ind = 1
      AND scm.trmn_dt > CURRENT_DATE()
      AND scm.primary_svc_cd = sp.service_code
),

cet_rates_result AS (
    SELECT 
        rr.service_code,
        rr.zip_code,
        rr.allowed_amount,
        rr.RATE_SYSTEM_CD,
        rr.GEOGRAPHIC_AREA_CD,
        cr.SPECIALTY_CD,
        cr.SPECIALTY_TYPE_CD,
        cr.rate
    FROM rate_results rr
    JOIN `prv_ps_ce_dec_hcb_dev.CET_RATES` cr
      ON cr.RATE_SYSTEM_CD = rr.RATE_SYSTEM_CD
     AND cr.GEOGRAPHIC_AREA_CD = rr.GEOGRAPHIC_AREA_CD
    WHERE cr.SERVICE_CD = rr.service_code
      AND cr.SERVICE_TYPE_CD = rr.service_type_code
      AND cr.PLACE_OF_SERVICE_CD = rr.place_of_service_code
      AND cr.CONTRACT_TYPE = rr.contract_type_standard
      -- AND cr.SPECIALTY_CD = rr.specialty_code
      AND cr.RATE = rr.allowed_amount
)

-- Final result: All test cases with rate_found flag
SELECT 
    tc.zip_code,
    tc.service_code,
    tc.allowed_amount,
    CASE WHEN cr.zip_code IS NOT NULL THEN 1 ELSE 0 END AS rate_found
FROM test_cases tc
LEFT JOIN cet_rates_result cr
  ON tc.zip_code = cr.zip_code
 AND tc.service_code = cr.service_code
 AND tc.allowed_amount = cr.allowed_amount
GROUP BY tc.zip_code, tc.service_code, tc.allowed_amount, rate_found
ORDER BY tc.zip_code, tc.service_code;
