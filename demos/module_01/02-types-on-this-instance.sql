-- instance: rpllab1
-- Module 1, clip 1.2: what this instance can do, read without creating anything.
-- The edition and the platform decide which replication types exist; one procedure,
-- sp_addpublication, creates snapshot, transactional, peer-to-peer and updatable
-- publications; merge has its own procedures; transactional needs a primary key.
SET NOCOUNT ON;

PRINT 'Edition, version and platform';
SELECT CAST(SERVERPROPERTY('Edition') AS nvarchar(60)) AS edition,
       SERVERPROPERTY('EngineEdition') AS engine_edition,
       SERVERPROPERTY('ProductVersion') AS product_version,
       SERVERPROPERTY('ProductUpdateLevel') AS update_level,
       h.host_platform, h.host_distribution
FROM sys.dm_os_host_info AS h;

PRINT 'Parameters of sp_addpublication that choose the type of publication';
SELECT p.name AS parameter, TYPE_NAME(p.user_type_id) AS data_type
FROM sys.all_parameters AS p
WHERE p.object_id = OBJECT_ID(N'sys.sp_addpublication')
  AND p.name IN (N'@repl_freq', N'@allow_sync_tran', N'@allow_queued_tran', N'@enabled_for_p2p',
                 N'@p2p_conflictdetection_policy', N'@enabled_for_het_sub')
ORDER BY p.parameter_id;

PRINT 'Merge replication has its own procedures, shipped on Linux too';
SELECT o.name AS procedure_name, COUNT(p.parameter_id) AS parameters
FROM sys.all_objects AS o
LEFT JOIN sys.all_parameters AS p ON p.object_id = o.object_id
WHERE o.name IN (N'sp_addpublication', N'sp_addmergepublication', N'sp_addarticle', N'sp_addmergearticle')
GROUP BY o.name
ORDER BY o.name;

PRINT 'Tables of PachadataTraining without a primary key: transactional replication refuses them';
SELECT s.name + N'.' + t.name AS table_name
FROM PachadataTraining.sys.tables AS t
JOIN PachadataTraining.sys.schemas AS s ON s.schema_id = t.schema_id
WHERE NOT EXISTS (SELECT * FROM PachadataTraining.sys.key_constraints AS k
                  WHERE k.parent_object_id = t.object_id AND k.type = 'PK')
ORDER BY table_name;
