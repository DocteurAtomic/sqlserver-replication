-- instance: rpllab3
-- Exercise of module 3, solution, on the subscriber: the Distribution Agent creates the tables,
-- not their schema. Without it, the delivery fails ("The specified schema name "Reference"
-- either does not exist").
SET NOCOUNT ON;
USE ex_ref;
IF SCHEMA_ID(N'Reference') IS NULL EXEC (N'CREATE SCHEMA Reference');
