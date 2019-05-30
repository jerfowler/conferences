USE CIS
GO


DECLARE @Invoices Table (
	InvoiceID varchar(15) NOT NULL,
	NewDueDate Datetime NOT NULL,
	UserID varchar(80) NOT NULL
)

DECLARE @InvoiceID varchar(15)
DECLARE @DueDate Datetime
DECLARE @User varchar(80) = 'Alissa Blackwell'
DECLARE @Date DateTime = GETDATE()
DECLARE @Msg varchar(255)

--INSERT INTO @Invoices
--VALUES 
--('923268','2/15/2019', @User),
--('925601','2/15/2019', @User)


--SELECT * from @Invoices


BEGIN TRANSACTION
BEGIN TRY
	ALTER TABLE [dbo].[InvoiceHeader] DISABLE TRIGGER trgInvoiceHeader_Update_Validate;
	SELECT TOP 1 @InvoiceID = InvoiceID, @DueDate = NewDueDate, @User = UserID FROM @Invoices
	WHILE @InvoiceID IS NOT NULL
	BEGIN
		SELECT @Msg = 'Invoice '+@InvoiceID+ ' Due Date was extended to '+CONVERT(VARCHAR, @DueDate, 101)

		INSERT INTO CIS..Activity (ReferenceID, Description, UserID, Date, StatusID, TypeID, SourceDateTime, ImageID)
		SELECT I.QuoteID, @Msg, @User, @Date, 'INV' as StatusID, 'I' as TypeID, @Date AS SourceDateTime, 0 as ImageID
		FROM AFD..AR AR 
		JOIN CIS..InvoiceHeader I ON AR.AIMInvoiceKey_FK = I.InvoiceKey_PK AND AR.Type='IN'
		WHERE I.InvoiceID = @InvoiceID

		UPDATE AR SET DueDate = @DueDate
		FROM AFD..AR AR 
		JOIN CIS..InvoiceHeader I ON AR.AIMInvoiceKey_FK = I.InvoiceKey_PK AND AR.Type='IN'
		WHERE I.InvoiceID = @InvoiceID

		UPDATE I SET DueDate = @DueDate
		FROM AFD..AR AR 
		JOIN CIS..InvoiceHeader I ON AR.AIMInvoiceKey_FK = I.InvoiceKey_PK AND AR.Type='IN'
		WHERE I.InvoiceID = @InvoiceID

		PRINT @Msg

		DELETE FROM @Invoices where InvoiceID = @InvoiceID
		SELECT @InvoiceID = NULL, @DueDate = NULL, @User = NULL
		SELECT TOP 1 @InvoiceID = InvoiceID, @DueDate = NewDueDate, @User = UserID FROM @Invoices
	END
	ALTER TABLE [dbo].[InvoiceHeader] ENABLE TRIGGER trgInvoiceHeader_Update_Validate;
	COMMIT TRANSACTION;
END TRY
BEGIN CATCH
	ROLLBACK TRANSACTION;
	ALTER TABLE [dbo].[InvoiceHeader] ENABLE TRIGGER trgInvoiceHeader_Update_Validate;
	THROW;
END CATCH;
