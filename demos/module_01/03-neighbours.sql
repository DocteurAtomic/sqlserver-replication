-- instance: rpllab1
-- Module 1, clip 1.3: the neighbours of replication, as flags of one database and of the
-- instance. Read-only. Replication, CDC, the Fabric change feed and change tracking are all
-- switched on per database; availability groups per instance.
SET NOCOUNT ON;

PRINT 'PachadataTraining: which features are on';
SELECT d.name, d.recovery_model_desc, d.log_reuse_wait_desc,
       d.is_published, d.is_merge_published, d.is_subscribed, d.is_distributor,
       d.is_cdc_enabled, d.is_change_feed_enabled, d.is_data_lake_replication_enabled,
       CASE WHEN ct.database_id IS NULL THEN 0 ELSE 1 END AS is_change_tracking_on
FROM sys.databases AS d
LEFT JOIN sys.change_tracking_databases AS ct ON ct.database_id = d.database_id
WHERE d.name = N'PachadataTraining';

PRINT 'The instance: availability groups';
SELECT SERVERPROPERTY('IsHadrEnabled') AS is_hadr_enabled,
       (SELECT COUNT(*) FROM sys.availability_groups) AS availability_groups;
