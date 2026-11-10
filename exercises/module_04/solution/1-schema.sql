-- instance: rpllab3
-- Exercise of module 4, solution, on the subscriber: the snapshot creates the tables, not their
-- schema (module 3).
SET NOCOUNT ON;
USE ex_catalog;
IF SCHEMA_ID(N'Course') IS NULL EXEC (N'CREATE SCHEMA Course');
