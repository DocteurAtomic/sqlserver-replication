-- instance: SQL01 (publisher and distributor)
-- ci: skip (Windows only)
-- Module 11, cleanup on the publisher: the merge subscriptions and publications of m11_pacha,
-- the database, the distributor and m11_distribution. Run 99-cleanup-subscriber.sql on the
-- subscriber, then delete C:\m11_repldata. Safe to run twice.
--   sqlcmd -S SQL01 -E -C -I -i 99-cleanup-publisher.sql
SET NOCOUNT ON;
USE master;
IF DB_ID(N'm11_pacha') IS NOT NULL
BEGIN
    EXEC (N'USE m11_pacha;
    DECLARE @p sysname;
    IF OBJECT_ID(N''dbo.sysmergepublications'') IS NOT NULL
    BEGIN
        DECLARE pubs CURSOR LOCAL FAST_FORWARD FOR
            SELECT name FROM dbo.sysmergepublications WHERE publisher_db = DB_NAME();
        OPEN pubs; FETCH pubs INTO @p;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sys.sp_dropmergesubscription @publication = @p, @subscriber = N''all'',
                 @subscriber_db = N''all'', @subscription_type = N''all'';
            EXEC sys.sp_dropmergepublication @publication = @p;
            FETCH pubs INTO @p;
        END;
        CLOSE pubs; DEALLOCATE pubs;
    END;');
    EXEC sys.sp_replicationdboption @dbname = N'm11_pacha', @optname = N'merge publish', @value = N'false';
    ALTER DATABASE m11_pacha SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE m11_pacha;
END;
GO
IF EXISTS (SELECT 1 FROM sys.servers WHERE is_distributor = 1)
   AND EXISTS (SELECT 1 FROM msdb.dbo.MSdistributiondbs WHERE name = N'm11_distribution')
BEGIN
    DECLARE @me sysname = @@SERVERNAME, @s sysname;
    -- subscribers registered by the push subscriptions
    DECLARE subs CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.servers WHERE is_subscriber = 1 AND server_id <> 0;
    OPEN subs; FETCH subs INTO @s;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        EXEC sys.sp_dropsubscriber @subscriber = @s, @ignore_distributor = 1;
        -- sp_dropsubscriber leaves the remote server entry behind
        IF EXISTS (SELECT 1 FROM sys.servers WHERE name = @s) EXEC sys.sp_dropserver @server = @s;
        FETCH subs INTO @s;
    END;
    CLOSE subs; DEALLOCATE subs;
    EXEC sys.sp_dropdistpublisher @publisher = @me;
    EXEC sys.sp_dropdistributiondb @database = N'm11_distribution';
    EXEC sys.sp_dropdistributor;
END;
GO
SELECT name FROM sys.databases WHERE name LIKE N'm11[_]%';
SELECT name, is_distributor, is_subscriber FROM sys.servers WHERE server_id <> 0;
SELECT j.name FROM msdb.dbo.sysjobs AS j WHERE j.name LIKE N'%m11[_]%';
EXEC sys.sp_get_distributor;
