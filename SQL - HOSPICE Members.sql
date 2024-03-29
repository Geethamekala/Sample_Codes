--The purpose of this query is to identify Hopspice claims for the members who have been in the hospice care and reprocess claims for recoupment because Medicare FFS (CMS) is responsible for 
--for the member's Part C claims during the hospice care period.

-------------------	CURRENT HOSPICE CUSTOMERS-------------------------
IF OBJECT_ID ('tempdb..#CURRENT_HOSPICEFLAG','U') IS NOT NULL DROP TABLE #CURRENT_HOSPICEFLAG
 SELECT DISTINCT MCH.Custormer_ID, P.*,'Y' AS CURRENT_HOSPICE
 INTO #CURRENT_HOSPICEFLAG
 FROM (SELECT * , ROW_NUMBER() OVER (PARTITION BY CMS_NUMBER ORDER BY PAYMENTDATE DESC) AS ROWN --identfying most current member hospice status
		FROM YOURSERVER.DATABASE.SCHEMA.TABLE
		WHERE CMS_CODE IS NULL AND HOSPICE ='Y' ) P
 LEFT JOIN YOURSERVER.DATABASE.SCHEMA.TABLE MCH ON MCH.CMS_ID =P.CMS_NUMBER
 WHERE P.ROWN =1 AND GETDATE() BETWEEN PAYMENT_STARTDATE AND PAYMENT_ENDTDATE 
 ORDER BY CMS_NUMBER 


-----------------------------ALL HOSPICE CUSTOMERS FROM LAST YEAR-----------------------------
IF OBJECT_ID ('tempdb..#ALL_HOSPICEFLAG','U') IS NOT NULL DROP TABLE #ALL_HOSPICEFLAG
SELECT DISTINCT MCH.Custormer_ID, CMS_R.*
INTO #ALL_HOSPICEFLAG
FROM (SELECT * 
		FROM YOURSERVER.DATABASE.SCHEMA.TABLE 
		WHERE HOSPICE ='Y'AND PAYMENT_STARTDATE >= '01/01/YYYY') CMS_R
LEFT JOIN YOURSERVER.DATABASE.SCHEMA.TABLE MCH ON MCH.CMS_ID =CMS_R.CMS_NUMBER
WHERE CMS_CODE IS NULL OR  CMS_CODE='XX'
ORDER BY PaymentDate 



------------------------ALL CLAIMS FOR ALL HOSPICE CUSTOMERS FROM THE LAST 365 DAYS----------------------------

IF OBJECT_ID ('TEMPDB..#HOSPICE_CLAIMS','U') IS NOT NULL DROP TABLE #HOSPICE_CLAIMS
SELECT DISTINCT Custormer_ID,CUSTOMER_ENROLL_ID, A.CLAIMID, ORIG_CLAIMID, STARTDATE, ENDDATE, A.[STATUS], TOTALPAID,PROVIDER_ID  
INTO #HOSPICE_CLAIMS
FROM YOURSERVER.DATABASE.SCHEMA.TABLE A
WHERE Custormer_ID IN (SELECT DISTINCT Custormer_ID 
						FROM #ALL_HOSPICEFLAG 
						WHERE Custormer_ID IS NOT NULL) 
AND STARTDATE >= DATEADD(year,-1,GETDATE()) AND A.STATUS LIKE '%XX%' AND (PLANID IS NULL OR PLANID IN ('PLAN01', 'PLAN02','PLAN03'))


------------------------BRINGING IN CLAIMS ONLY FROM THE PERIOD OF CUSTOMER'S HOSPICE CARE ----------------------------------

IF OBJECT_ID ('TEMPDB..#HOSPICE_CLAIMS_FINAL','U') IS NOT NULL DROP TABLE #HOSPICE_CLAIMS_FINAL
SELECT DISTINCT AH.CMS_NUMBER AS CMSCUSTOMER_ID,[MONTH],HC.*
INTO  #HOSPICE_CLAIMS_FINAL
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY Custormer_ID,CUSTOMER_ENROLL_ID,ORIG_CLAIMID,STARTDATE,ENDDATE  ORDER BY CLAIMID DESC) ROW_NUM FROM #HOSPICE_CLAIMS) HC
LEFT JOIN #ALL_HOSPICEFLAG  AH ON AH.Custormer_ID =HC.Custormer_ID
LEFT JOIN (SELECT DISTINCT PK_DATE, [MONTH] FROM YOURSERVER.DATABASE.SCHEMA.TABLE ) T ON CAST(STARTDATE AS DATE) = CAST(PK_DATE AS DATE)
WHERE HC.STARTDATE BETWEEN PAYMENT_STARTDATE AND PAYMENT_ENDTDATE AND ROW_NUM =1 AND TOTALPAID > 0
ORDER BY [MONTH],Custormer_ID



--------------------------BRINGINING IN CUSTOMER DEMOGAPCMS_ID AND PRIVIDER INFORMATION------------------
IF OBJECT_ID ('TEMPDB..#MEM_DEMO','U') IS NOT NULL DROP TABLE #MEM_DEMO
SELECT DISTINCT HCF.*
		,EK.CUSTOMER_ID2
		,MEM.[CUSTOMER_NAME]
		,MEM.[CUSTOMER_DOB_DATE]
		,MEM.[CUSTOMER_GENDER]
		,ENT.[CUSTOMER_ADDRESS_1]
		,ENT.[CUSTOMER_ADDRESS_2]
		,RTRIM(ENT.city) +', ' + ENT.STATE as [CUSTOMER_CITY_STATE]
		,ENT.[CUSTOMER_ZIP]
		,ENT.[CUSTOMER_TELEPHONE]
		,Min(EK.CUSTOMER_EFFECTIVEDATE) over(partition by MEM.Custormer_ID, programid) as [EFF_DATE]
		,max(isnull(EK.CUSTOMER_TERMINATIONDATE,'12/31/YYYY'))over(partition by MEM.Custormer_ID, programid) as [TERM_DATE] 
		, Case when programid = 'PROGRAM_ID01' then 'PLAN01' else 'PLAN02' end as PROGRAM_ENROLLMENT
		,ISNULL(CHF.CURRENT_HOSPICE, 'N') AS CURRENT_HOSPICE
INTO #MEM_DEMO		 
FROM #HOSPICE_CLAIMS_FINAL HCF
LEFT JOIN YOURSERVER.DATABASE.SCHEMA.TABLE MEM ON MEM.Custormer_ID = HCF.Custormer_ID 
LEFT JOIN YOURSERVER.DATABASE.SCHEMA.TABLE EK ON EK.Custormer_ID =HCF.Custormer_ID
LEFT JOIN YOURSERVER.DATABASE.SCHEMA.TABLE ENT on ENT.CUSTOMER_ID3 = MEM.CUSTOMER_ID3
LEFT JOIN #CURRENT_HOSPICEFLAG CHF ON CHF.Custormer_ID =HCF.Custormer_ID
WHERE  EK.programid in ('PROGRAM_ID01','PROGRAM_ID02') AND EK.CUSTOMER_ENROLL_ID <> '' AND EK.CUSTOMER_EFFECTIVEDATE < EK.CUSTOMER_TERMINATIONDATE



SELECT DISTINCT MD.[MONTH],Custormer_ID,CMSCUSTOMER_ID,CLAIMID,ORIG_CLAIMID,STARTDATE AS DOS_STARTDATE, ENDDATE AS DOS_ENDDATE, MD.[STATUS] AS [CLAIM_STATUS], TOTALPAID,
MD.CUSTOMER_NAME,CUSTOMER_DOB_DATE, CUSTOMER_GENDER,RTRIM(CUSTOMER_ADDRESS_1)+' '+ CUSTOMER_ADDRESS_2 AS CUSTOMER_ADDRESS, RTRIM(CUSTOMER_CITY_STATE)+' '+CUSTOMER_ZIP AS CUSTOMER_CITY_STATE_ZIP, 
CUSTOMER_TELEPHONE,CASE WHEN GETDATE() BETWEEN EFF_DATE AND TERM_DATE THEN 'CURRENT' ELSE 'PAST' END AS  CUSTOMER_STATUS,EFF_DATE, TERM_DATE, PROGRAM_ENROLLMENT,CURRENT_HOSPICE,CH.VENDOR_PROV_ID AS PROVIDER_ID,CH.VENDOR AS PROVIDER_NAME,PR1.PROVIDER_ID2 AS PROVIDER_IDER_PROVIDER_ID2
,CH.VENDOR_ID AS [MED_PRAC_NUM],CH.MASTER_VENDOR AS [MED_PRAC], PROV_ADDRESS
,PROV_CITY_STATE_ZIP, CONVERT(VARCHAR(7), STARTDATE, 120) AS MTH_YYYY
FROM  #MEM_DEMO MD
LEFT JOIN  YOURSERVER.DATABASE.SCHEMA.TABLE PR1 ON PR1.PROVIDER_ID = MD.PROVIDER_ID
LEFT JOIN YOURSERVER.DATABASE.SCHEMA.TABLE CH ON CH.CLAIM_NUM =MD.CLAIMID
LEFT JOIN YOURSERVER.DATABASE.SCHEMA.TABLE E1 ON PR1.CUSTOMER_ID3 = E1.CUSTOMER_ID3
order by dos_startdate
 







