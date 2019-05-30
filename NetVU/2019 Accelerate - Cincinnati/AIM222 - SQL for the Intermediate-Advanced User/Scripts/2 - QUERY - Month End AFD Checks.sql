USE AFD
GO

--select * FROM tacAcctMaster 

DECLARE @ARAcct varchar(5) = '1100'
DECLARE @CRAcct varchar(5) = '1200'
DECLARE @APAcct varchar(5) = '2000'
DECLARE @PPAcct varchar(5) = '2100'
DECLARE @TPAcct varchar(5) = '2200'
DECLARE @ClearAcct varchar(5) = '2300'

DECLARE @Period varchar(4) = '1905'

DECLARE @RealPeriod varchar(6), @StartDate DateTime, @EndDate DateTime

SELECT @RealPeriod = RealPeriod, @StartDate = StartDate, @EndDate=EndDate 
FROM PERIODS WITH (NOLOCK)
WHERE PERIOD = @Period

-- Check All GL Batches Balances to zero
select date, batch, SUM((ISNULL(Debit, 0)) - (ISNULL(Credit, 0))) Amount,[Date]
  FROM [AFD].[dbo].[GL] GL WITH (NOLOCK)
  WHERE  [Date] BETWEEN @StartDate AND @EndDate
  GROUP BY [Date], batch
  having SUM((ISNULL(Debit, 0)) - (ISNULL(Credit, 0))) <> 0

-- Check All AR balances match the transactions
select AR.BatchKey_PK, ID, AR.Reference, PolicyID, InvNo, Date, DueDate, Description, Amt, Bal, ARBal.Balance, PendingPay, PostingBatchKey_FK, PaidToZeroBatch_FK
--UPDATE AR SET Bal = ARBal.Balance
from AR
join
	(
	SELECT Reference, Sum(CASE When AR.Type in ('IN', 'DR') THEN AR.Amt Else -AR.Amt END) as Balance
	FROM [AFD].[dbo].[AR] AR WITH (NOLOCK) 
	GROUP BY Reference
) ARBal ON AR.Reference = ARBal.Reference
WHERE AR.Type = 'IN' --and InvNo like 'COB%'
AND ARBal.Balance <> AR.Bal

--Check all AP balances match the transactions
select AP.BatchKey_PK, ID, AP.Reference, SubLedger, PolicyID, InvNo, Date, DueDate, Description, Amt, Bal, APBal.Balance, PendingPay, PostingBatchKey_FK
--UPDATE AP SET Bal = APBal.Balance
from AP
join (
	SELECT Reference, SUM(CASE WHEN AP.Type in ('IN','CR','CA') THEN AP.Amt ELSE -AP.Amt END) AS Balance
	FROM [AFD].[dbo].[AP] AP (NOLOCK)
	GROUP BY Reference
) APBal ON AP.Reference = APBal.Reference
WHERE AP.Type = 'IN'
AND AP.Bal <> APBal.Balance

--Check all AP PendingBatchKeys are valid unposted batches
select B.Date, B.BatchKey_PK, B.Posted, A.BatchKey_PK, A.InvNo, A.Date, A.Amt, A.Bal, A.PendingBatchKey_FK, PendingPay, DBPendingPay, PendingVoucherKey_FK, PendingItemCount
--update A SET PendingBatchKey_FK = null, PendingPay = null, DBPendingPay = null, PendingVoucherKey_FK = Null, PendingItemCount = null
from AP A
join BatchTTL B ON A.PendingBatchKey_FK = B.BatchKey_PK
where B.Posted = 'Y'

--Check all AR PendingBatchKeys are valid unposted batches
select B.Date, B.BatchKey_PK, B.Posted, A.BatchKey_PK, A.InvNo, A.Date, A.Amt, A.Bal, A.PendingBatchKey_FK, A.PendingPay, A.PendingVoucherKey_FK
--update A SET PendingBatchKey_FK = null, PendingPay = null, PendingVoucherKey_FK = Null
from AR A
join BatchTTL B ON A.PendingBatchKey_FK = B.BatchKey_PK
where B.Posted = 'Y'

-- Check the Subledgers balance to the GL
SELECT Account, Description, Date, SUM(GL) AS GL, SUM(SubLedger) AS SubLedger, SUM(GL) - SUM(SubLedger) AS Diff
FROM (
	select ACCT.Account, ACCT.Description
	, CASE WHEN Date BETWEEN @StartDate AND @EndDate THEN Date ELSE @StartDate END AS Date
	, SUM(ISNULL(DEBIT,0)-ISNULL(CREDIT,0)) AS GL
	, 0 AS SubLedger
	FROM GL WITH (NOLOCK)
	JOIN ACCT WITH (NOLOCK) ON GL.ACCT = ACCT.ACCT
	WHERE (Period <= @Period OR RealPeriod <= @RealPeriod)
	AND ACCT.Account IN (@ARAcct,@CRAcct,@APAcct,@PPAcct,@TPAcct)
	GROUP BY ACCT.Account, ACCT.Description, CASE WHEN Date BETWEEN @StartDate AND @EndDate THEN Date ELSE @StartDate END

	UNION ALL

	select ACCT.Account, ACCT.Description
	, CASE WHEN Date BETWEEN @StartDate AND @EndDate THEN Date ELSE @StartDate END AS Date
	, 0 AS GL 
	, Sum(CASE When Type in ('IN', 'DR') THEN Amt Else -Amt END) AS SubLedger
	FROM AR WITH (NOLOCK)
	JOIN (
		SELECT 'AR' as SubLedger, Account, Description FROM tacAcctMaster WHERE Account = @ARAcct
		UNION ALL
		SELECT 'CR' as SubLedger, Account, Description FROM tacAcctMaster WHERE Account = @CRAcct
	) ACCT ON ACCT.SubLedger = AR.SubLedger
	WHERE (Period <= @Period OR RealPeriod <= @RealPeriod)
	GROUP BY ACCT.Account, ACCT.Description, CASE WHEN Date BETWEEN @StartDate AND @EndDate THEN Date ELSE @StartDate END

	UNION ALL

	select ACCT.Account, ACCT.Description
	, CASE WHEN Date BETWEEN @StartDate AND @EndDate THEN Date ELSE @StartDate END AS Date
	, 0 AS GL 
	, SUM(CASE WHEN AP.Type in ('IN','CR','CA') THEN -AP.Amt ELSE AP.Amt END) AS SubLedger
	FROM AP WITH (NOLOCK)
	JOIN (
		SELECT 'AP' as SubLedger, Account, Description FROM tacAcctMaster WHERE Account = @APAcct
		UNION ALL
		SELECT 'PP' as SubLedger, Account, Description FROM tacAcctMaster WHERE Account = @PPAcct
		UNION ALL
		SELECT 'TP' as SubLedger, Account, Description FROM tacAcctMaster WHERE Account = @TPAcct
	) ACCT ON ACCT.SubLedger = AP.SubLedger
	WHERE (Period <= @Period OR RealPeriod <= @RealPeriod)
	  AND AP.SubLedger IN ('AP','PP','TP')
	GROUP BY ACCT.Account, ACCT.Description, CASE WHEN Date BETWEEN @StartDate AND @EndDate THEN Date ELSE @StartDate END 
) X
GROUP BY Account, Description, Date
HAVING SUM(GL) - SUM(SubLedger)  <> 0
ORDER BY Account, Date

-- Verify the 2300 Clearing Premium accounts balance to zero
select GL.ACCT, ACCT.Account, ACCT.Description
	, CASE WHEN Date BETWEEN @StartDate AND @EndDate THEN Date ELSE @StartDate END AS Date
	, SUM(ISNULL(GL.CREDIT,0) - ISNULL(GL.DEBIT,0)) AS Revenue
from GL WITH (NOLOCK) 
join ACCT WITH (NOLOCK) ON GL.ACCT = ACCT.ACCT
where (Period <= @Period OR RealPeriod <= @RealPeriod)
	AND ACCT.Account = @ClearAcct
GROUP BY GL.ACCT, ACCT.Account, ACCT.Description, CASE WHEN Date BETWEEN @StartDate AND @EndDate THEN Date ELSE @StartDate END
HAVING SUM(ISNULL(GL.CREDIT,0) - ISNULL(GL.DEBIT,0)) <> 0

--Verify the dates are all within the period
SELECT * FROM GL WITH (NOLOCK) WHERE (Period = @Period OR RealPeriod = @RealPeriod) AND NOT Date BETWEEN @StartDate AND @EndDate ORDER BY BATCH, Date
SELECT * FROM AR WITH (NOLOCK) WHERE (Period = @Period OR RealPeriod = @RealPeriod) AND NOT Date BETWEEN @StartDate AND @EndDate
SELECT * FROM AP WITH (NOLOCK) WHERE (Period = @Period OR RealPeriod = @RealPeriod) AND NOT Date BETWEEN @StartDate AND @EndDate

--Verify all transactions on an invoice are in the same AR subledger
SELECT AR.ID, AR.BatchKey_PK, AR.InvNo, AR.Date, AR.Period, AR.Amt, AR.SubLedger, AR.Type, AR.Description, 
AR2.ID, AR2.BatchKey_PK, AR2.InvNo, AR2.Date, AR2.Period, AR2.Amt, AR2.SubLedger, AR2.Type, AR2.Description
FROM AR AR WITH (NOLOCK)
JOIN AR AR2 WITH (NOLOCK) ON AR.Reference = AR2.Reference 
WHERE AR.Type = 'IN' 
  AND AR2.Type <> 'IN'
  AND AR.SubLedger <> AR2.SubLedger
  AND (AR.Period = @Period OR AR2.Period = @Period)
ORDER BY AR.Reference

--Verify all transactions on an invoice are in the same AP subledger
SELECT * 
FROM AP AP WITH (NOLOCK)
JOIN AP AP2 WITH (NOLOCK) ON AP.Reference = AP2.Reference 
WHERE AP.Type = 'IN' 
  AND AP2.Type <> 'IN'
  AND AP.ID = AP2.ID
  AND AP.SubLedger <> AP2.SubLedger
  AND (AP.Period = @Period OR AP2.Period = @Period)

SELECT *
FROM (SELECT ISNULL(PaymentKey_FK,PaidVoucherKey_FK) AS PaymentKey_FK, PostingBatchKey_FK, Date, SUM(CASE WHEN Type = 'DR' THEN -Amt ELSE Amt END) AS ARAmt 
	  FROM AR WITH (NOLOCK) 
	  WHERE Type IN ('PA', 'UN', 'DR', 'CR') AND RealPeriod=@RealPeriod
	  GROUP BY ISNULL(PaymentKey_FK,PaidVoucherKey_FK), PostingBatchKey_FK, Date) AR
JOIN (SELECT VoucherKey_FK, BatchKey_FK, Date, SUM(CREDIT) AS GLAmt 
	  FROM GL WITH (NOLOCK) 
	  WHERE Acct like '%'+@ARAcct AND RealPeriod=@RealPeriod
	  GROUP BY VoucherKey_FK, BatchKey_FK, Date) GL ON AR.PaymentKey_FK=GL.VoucherKey_FK AND AR.PostingBatchKey_FK = GL.BatchKey_FK
WHERE AR.ARAmt <> GL.GLAmt

SELECT *
FROM (SELECT PostingBatchKey_FK, SUM(Amt) AS ARAmt, Sum(CASE When Type in ('IN', 'DR') THEN Amt Else -Amt END) AS Bal 
	  FROM AR WITH (NOLOCK) 
	  WHERE SubLedger = 'AR' AND RealPeriod=@RealPeriod
	  GROUP BY PostingBatchKey_FK) AR
JOIN (SELECT BatchKey_FK, SUM(ISNULL(CREDIT,0)) AS Credit, SUM(ISNULL(DEBIT,0)) AS Debit, SUM(ISNULL(CREDIT,0)) - SUM(ISNULL(DEBIT,0))  AS GLAmt 
	  FROM GL (NOLOCK) 
	  WHERE Acct like '%'+@ARAcct AND RealPeriod=@RealPeriod
	  GROUP BY BatchKey_FK) GL ON AR.PostingBatchKey_FK = GL.BatchKey_FK
WHERE ABS(AR.Bal) <> ABS(GL.GLAmt)

SELECT *
FROM (SELECT PaymentKey_FK, PostingBatchKey_FK, Date, SUM(Amt) AS ARAmt 
	  FROM AR WITH (NOLOCK)
	  WHERE Type IN ('PA', 'UN') AND RealPeriod=@RealPeriod
	  GROUP BY PaymentKey_FK, PostingBatchKey_FK, Date) AR
JOIN (SELECT VoucherKey_FK, BatchKey_FK, Date, SUM(CREDIT) AS GLAmt 
	  FROM GL WITH (NOLOCK)
	  WHERE Acct like '%'+@CRAcct AND RealPeriod=@RealPeriod
	  GROUP BY VoucherKey_FK, BatchKey_FK, Date) GL ON AR.PaymentKey_FK=GL.VoucherKey_FK AND AR.PostingBatchKey_FK = GL.BatchKey_FK
WHERE AR.ARAmt <> GL.GLAmt

SELECT *
FROM (SELECT PostingBatchKey_FK, SUM(Amt) AS ARAmt, Sum(CASE When Type in ('IN', 'DR') THEN Amt Else -Amt END) AS Bal 
	  FROM AR WITH (NOLOCK)
	  WHERE SubLedger = 'CR' AND RealPeriod=@RealPeriod
	  GROUP BY PostingBatchKey_FK) AR
JOIN (SELECT BatchKey_FK, SUM(ISNULL(CREDIT,0)) AS Credit, SUM(ISNULL(DEBIT,0)) AS Debit, SUM(ISNULL(CREDIT,0)) - SUM(ISNULL(DEBIT,0))  AS GLAmt 
	  FROM GL WITH (NOLOCK)
	  WHERE Acct like '%'+@CRAcct AND RealPeriod=@RealPeriod
	  GROUP BY BatchKey_FK) GL ON AR.PostingBatchKey_FK = GL.BatchKey_FK
WHERE ABS(AR.Bal) <> ABS(GL.GLAmt)

