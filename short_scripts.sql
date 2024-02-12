-- service accounts
SELECT servicename, service_account
FROM sys.dm_server_services

-- kill all sessions (independent version)
DECLARE @kill varchar(8000) = ''; 
 CREATE TABLE #sp_who2 (SPID INT,Status VARCHAR(255),
	  Login  VARCHAR(255),HostName  VARCHAR(255),
	  BlkBy  VARCHAR(255),DBName  VARCHAR(255),
	  Command VARCHAR(255),CPUTime INT,
	  DiskIO INT,LastBatch VARCHAR(255),
	  ProgramName VARCHAR(255),SPID2 INT,
	  REQUESTID INT)
INSERT INTO #sp_who2 EXEC sp_who2
SELECT @kill = @kill + 'kill ' + CONVERT(varchar(5), SPID) + ';'  
FROM #sp_who2
WHERE DBName  = 'DB_NAME'
EXEC(@kill)
drop table #sp_who2
	
-- Backup exec time
SELECT session_id as SPID, command, a.text AS Query, start_time, percent_complete, dateadd(second,estimated_completion_time/1000, getdate()) as estimated_completion_time
	FROM sys.dm_exec_requests r CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) a
	WHERE r.command in ('BACKUP DATABASE','RESTORE DATABASE')  
	
	
-- Login mapping
create table #loginmappings(  
 LoginName  nvarchar(128) NULL,  
 DBName     nvarchar(128) NULL,  
 UserName   nvarchar(128) NULL,  
 AliasName  nvarchar(128) NULL 
)  
insert into #loginmappings
EXEC master..sp_msloginmappings
select * from #loginmappings
DROP TABLE #loginmappings


--List HeadLock
select DB_NAME(a.dbid) db_name,spid processId, waittime, last_batch as time, cpu, memusage, physical_io, sqlText.text QUERY
  from  master..sysprocesses a
  OUTER APPLY master.sys.dm_exec_sql_text(a.sql_handle) sqlText
 where  exists ( select b.*
    from master..sysprocesses b
    where b.blocked > 0 and 
   b.blocked = a.spid ) and not
 exists ( select b.*
     from master..sysprocesses b
    where b.blocked > 0 and
   b.spid = a.spid ) 
  
--DB size
SELECT DB_NAME(database_id) 'DbName',name logicDisk, physical_name physical_disk, state_desc status, CAST(size/1024 as VARCHAR(MAX))+'MB' currentSize,  
case WHEN max_size <> -1 THEN CAST(max_size/1024 as VARCHAR(MAX))+'MB'
	ELSE 'unlimited'
END  max_size
,CASE WHEN is_percent_growth <> 1 THEN 
	 CAST(growth as VARCHAR(MAX))+'KB'
	ELSE CAST(growth as VARCHAR(MAX))+'%'
	end growthVal
,case 
	when size > max_size*0.9 AND max_size <> -1 THEN 'Less than 10%'
	when size > max_size*0.8 AND max_size <> -1 THEN 'Less than 20%'
	when size > max_size*0.7 AND max_size <> -1 THEN 'Less than 30%'
	when size > max_size*0.6 AND max_size <> -1 THEN 'Less than 40%'
	when size > max_size*0.5 AND max_size <> -1 THEN 'Less than 50%'
	else 'OK'
	END 'InfoWarning'
FROM sys.master_files
WHERE database_id > 4

--Active sessions
SELECT distinct  @@SERVERNAME SERVER,
   s.login_name login,  
   ISNULL(db_name(p.dbid), N'') db_name,
   ISNULL(s.program_name, N'') app,
   ISNULL(s.host_name, N'') host_name,
   CONVERT(date,  s.login_time) login_time,
   sqlText.text
FROM sys.dm_exec_sessions s LEFT OUTER JOIN sys.dm_exec_connections c ON (s.session_id = c.session_id)
LEFT OUTER JOIN sys.dm_resource_governor_workload_groups g ON (g.group_id = s.group_id)
LEFT OUTER JOIN sys.sysprocesses p ON (s.session_id = p.spid)

  OUTER APPLY master.sys.dm_exec_sql_text(p.sql_handle) sqlText
where CONVERT(CHAR(1), s.is_user_process)=1 and ISNULL(c.client_net_address, N'')<>'<local machine>'
AND p.dbid > 4


