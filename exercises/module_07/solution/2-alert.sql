-- instance: rpllab2
-- Exercise of module 7, solution, part 2: the response to the failure of an agent. The alert
-- "Replication: agent failure" (14151) enabled: on Windows, it fires and can notify an operator;
-- on Linux the alert engine of SQL Server Agent is disabled, and it never fires. The agents write
-- the same failure to msdb.dbo.sysreplicationalerts on both systems: the job
-- ex_agent_failure_watch, every minute, copies the new 14151 rows to ex_monitor.dbo.AgentFailure
-- and marks them as serviced (status 1), the framework Learn describes for automated responses.
SET NOCOUNT ON;
EXEC msdb.dbo.sp_update_alert @name = N'Replication: agent failure', @enabled = 1;
EXEC msdb.dbo.sp_add_job @job_name = N'ex_agent_failure_watch', @enabled = 1,
     @description = N'Copies the failures of the replication agents (14151) to ex_monitor.dbo.AgentFailure.';
EXEC msdb.dbo.sp_add_jobstep @job_name = N'ex_agent_failure_watch', @step_name = N'Copy the new failures',
     @subsystem = N'TSQL', @database_name = N'msdb', @command = N'
INSERT ex_monitor.dbo.AgentFailure (alert_id, time, agent_type, subscriber_db, error_text)
SELECT alert_id, time, agent_type, subscriber_db, alert_error_text
FROM msdb.dbo.sysreplicationalerts
WHERE alert_error_code = 14151 AND status = 0
  AND alert_id NOT IN (SELECT alert_id FROM ex_monitor.dbo.AgentFailure);
UPDATE msdb.dbo.sysreplicationalerts SET status = 1
WHERE alert_error_code = 14151 AND status = 0
  AND alert_id IN (SELECT alert_id FROM ex_monitor.dbo.AgentFailure);';
EXEC msdb.dbo.sp_add_jobschedule @job_name = N'ex_agent_failure_watch', @name = N'Every minute',
     @freq_type = 4, @freq_interval = 1, @freq_subday_type = 4, @freq_subday_interval = 1;
EXEC msdb.dbo.sp_add_jobserver @job_name = N'ex_agent_failure_watch', @server_name = N'(local)';
SELECT name, enabled, occurrence_count FROM msdb.dbo.sysalerts WHERE message_id = 14151;
SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name = N'ex_agent_failure_watch';
