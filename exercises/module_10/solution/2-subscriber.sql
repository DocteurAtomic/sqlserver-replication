-- instance: rpllab3
-- Exercise of module 10, solution, on the subscriber: the login of the Distribution Agent, a
-- user in ex_catalog with the role db_owner, no server role.
SET NOCOUNT ON;
CREATE LOGIN ex_distrib WITH PASSWORD = N'Distrib-2026!ex', CHECK_POLICY = OFF;
USE ex_catalog;
CREATE USER ex_distrib FOR LOGIN ex_distrib;
ALTER ROLE db_owner ADD MEMBER ex_distrib;
