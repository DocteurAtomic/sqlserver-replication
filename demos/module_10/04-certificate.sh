#!/usr/bin/env bash
# ci: skip (two more SQL Server containers, 4 GB, and openssl on the host)
# Module 10, clip 10.3. The certificate the instances trust, in place of
# @trust_distributor_certificate. It does not touch the lab: two throwaway containers,
# m10tls1 (publisher) and m10tls2 (distributor), on their own network, each with a certificate
# signed by a certificate authority made for the occasion (openssl, CN and DNS name = the
# container name), set by network.tlscert and network.tlskey in mssql.conf. sp_adddistributor
# without @trust_distributor_certificate fails twice on the publisher while it does not trust
# the authority (HResult 0x80090301); once the authority is in the store of the operating
# system of the container (update-ca-certificates, no restart), the same call works and the
# link to the distributor is encrypted. Then a publication on m10tls1, whose Log Reader Agent
# connects with -EncryptionLevel 2, then 4, the authority being trusted on m10tls2 too.
# The two containers and the network are removed at the end (99-cleanup.sh does it too if a
# run stops before).
# Usage: ./demos/module_10/04-certificate.sh     (with Podman: ENGINE=podman ./demos/module_10/04-certificate.sh)
set -euo pipefail
cd "$(dirname "$0")/../.."
. setup/lib.sh
image=$(sed -n 's/^ *image: *//p' compose.yaml | head -1)
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
q() {  # sqlcmd in a throwaway container
    local c=$1; shift
    $engine exec -i "$c" /opt/mssql-tools18/bin/sqlcmd -S 127.0.0.1 -U sa -C -b -I -W "$@"
}
filter() { grep -v "^DBCC\|^WARNING\|^$\|^Creat\|^Dropping\|^Adding\|^Configuration option\|^ $" || true; }

echo "== A certificate authority and two server certificates"
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$dir/ca.key" -out "$dir/ca.crt" -days 30 -subj "/CN=m10 lab CA" 2> /dev/null
for h in m10tls1 m10tls2; do
    mkdir -p "$dir/$h"
    openssl req -newkey rsa:2048 -nodes -keyout "$dir/$h/$h.key" -out "$dir/$h.csr" -subj "/CN=$h" 2> /dev/null
    printf 'subjectAltName=DNS:%s\nextendedKeyUsage=serverAuth\nkeyUsage=digitalSignature,keyEncipherment\n' $h > "$dir/$h.ext"
    openssl x509 -req -in "$dir/$h.csr" -CA "$dir/ca.crt" -CAkey "$dir/ca.key" -CAcreateserial \
        -out "$dir/$h/$h.crt" -days 30 -extfile "$dir/$h.ext" 2> /dev/null
    chmod 755 "$dir/$h"; chmod 644 "$dir/$h/"*
    printf '[network]\ntlscert = /var/opt/mssql/tls/%s.crt\ntlskey = /var/opt/mssql/tls/%s.key\n' $h $h > "$dir/$h.conf"
    openssl x509 -in "$dir/$h/$h.crt" -noout -subject -issuer -ext subjectAltName | tr -s ' ' | paste -sd ' '
done

echo
echo "== Two throwaway containers"
$engine network create m10tls-net > /dev/null
for h in m10tls1 m10tls2; do
    $engine create --name $h --hostname $h --network m10tls-net --memory 2g --cpus 2 \
        -e ACCEPT_EULA=Y -e MSSQL_PID=Developer -e MSSQL_AGENT_ENABLED=true \
        -e MSSQL_SA_PASSWORD='Repl-2026!lab' -e SQLCMDPASSWORD='Repl-2026!lab' "$image" > /dev/null
    $engine cp "$dir/$h" $h:/var/opt/mssql/tls
    $engine cp "$dir/$h.conf" $h:/var/opt/mssql/mssql.conf
    $engine start $h > /dev/null
done
for h in m10tls1 m10tls2; do
    for i in $(seq 1 90); do q $h -Q "SELECT 1" > /dev/null 2>&1 && break; sleep 1; done
    # The Agent jobs cannot be created while it starts.
    for i in $(seq 1 60); do
        [ "$(q $h -h -1 -Q "SET NOCOUNT ON; DECLARE @r int; EXEC @r = msdb.dbo.sp_is_sqlagent_starting; SELECT @r" 2>/dev/null | tr -d '[:space:]')" = 0 ] && break; sleep 1
    done
done
$engine exec m10tls2 grep "successfully loaded for encryption" /var/opt/mssql/log/errorlog | sed 's/^[0-9-]* [0-9:.]* *[a-z0-9]* *//'

echo
echo "== m10tls2: the distributor"
$engine exec m10tls2 mkdir -p /var/opt/mssql/repldata
q m10tls2 -Q "SET NOCOUNT ON;
    EXEC sys.sp_adddistributor @distributor = N'm10tls2', @password = N'Dist-2026!lab';
    EXEC sys.sp_adddistributiondb @database = N'distribution', @security_mode = 1;
    EXEC sys.sp_adddistpublisher @publisher = N'm10tls1', @distribution_db = N'distribution', @security_mode = 0,
         @login = N'sa', @password = N'Repl-2026!lab', @working_directory = N'/var/opt/mssql/repldata';" 2>&1 | filter
q m10tls2 -Q "SET NOCOUNT ON; SELECT name, is_distributor FROM sys.databases WHERE name = N'distribution';"

echo
echo "== m10tls1: the distributor, without @trust_distributor_certificate"
for k in 1 2; do
    echo "-- attempt $k"
    q m10tls1 -Q "EXEC sys.sp_adddistributor @distributor = N'm10tls2', @password = N'Dist-2026!lab';" 2>&1 | filter || true
done
echo "-- m10tls1: the authority in the store of the operating system, as root"
$engine cp "$dir/ca.crt" m10tls1:/tmp/m10-lab-ca.crt
$engine exec -u 0 m10tls1 sh -c 'cp /tmp/m10-lab-ca.crt /usr/local/share/ca-certificates/ && update-ca-certificates 2>&1 | tail -1'
echo "-- attempt 3, no restart"
q m10tls1 -Q "EXEC sys.sp_adddistributor @distributor = N'm10tls2', @password = N'Dist-2026!lab';" 2>&1 | filter
q m10tls1 -Q "SET NOCOUNT ON; EXEC sys.sp_get_distributor;"
echo "-- m10tls2: the link of the publisher"
q m10tls2 -Q "SET NOCOUNT ON;
    SELECT DISTINCT s.login_name, c.encrypt_option FROM sys.dm_exec_sessions s JOIN sys.dm_exec_connections c ON c.session_id = s.session_id
    WHERE s.login_name = N'distributor_admin';"

echo
echo "== A publication on m10tls1, its Log Reader Agent on m10tls2"
$engine cp "$dir/ca.crt" m10tls2:/tmp/m10-lab-ca.crt
$engine exec -u 0 m10tls2 sh -c 'cp /tmp/m10-lab-ca.crt /usr/local/share/ca-certificates/ && update-ca-certificates 2>&1 | tail -1'
q m10tls1 -Q "SET NOCOUNT ON; CREATE DATABASE m10_tls;"
q m10tls1 -d m10_tls -Q "SET NOCOUNT ON;
    CREATE TABLE dbo.Probe (ProbeId int PRIMARY KEY, Label varchar(20)); INSERT dbo.Probe VALUES (1, 'first');
    EXEC sys.sp_replicationdboption @dbname = N'm10_tls', @optname = N'publish', @value = N'true';
    EXEC sys.sp_addlogreader_agent @job_login = NULL, @job_password = NULL,
         @publisher_security_mode = 0, @publisher_login = N'sa', @publisher_password = N'Repl-2026!lab';
    EXEC sys.sp_addpublication @publication = N'm10_pubTls', @repl_freq = N'continuous', @status = N'active',
         @sync_method = N'concurrent', @independent_agent = N'true', @immediate_sync = N'true', @allow_push = N'true';
    EXEC sys.sp_addarticle @publication = N'm10_pubTls', @article = N'Probe', @source_owner = N'dbo', @source_object = N'Probe';" 2>&1 | filter
job=$(q m10tls2 -h -1 -Q "SET NOCOUNT ON; SELECT j.name FROM msdb.dbo.sysjobs j JOIN msdb.dbo.syscategories c ON c.category_id = j.category_id WHERE c.name = N'REPL-LogReader';" | sed -n 1p | tr -d '[:space:]')
encryption() {  # -EncryptionLevel on the command of the Log Reader Agent, restart, connections
    q m10tls2 -Q "SET NOCOUNT ON;
        DECLARE @c nvarchar(max) = (SELECT js.command FROM msdb.dbo.sysjobsteps js JOIN msdb.dbo.sysjobs j ON j.job_id = js.job_id WHERE j.name = N'$job' AND js.step_id = 2);
        SET @c = RTRIM(LEFT(@c, CHARINDEX(N' -EncryptionLevel', @c + N' -EncryptionLevel') - 1)) + IIF(N'$1' = N'', N'', N' -EncryptionLevel $1');
        EXEC msdb.dbo.sp_update_jobstep @job_name = N'$job', @step_id = 2, @command = @c;
        IF EXISTS (SELECT * FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id WHERE j.name = N'$job'
                   AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions))
            EXEC msdb.dbo.sp_stop_job @job_name = N'$job';" > /dev/null
    for i in $(seq 1 60); do
        [ "$(q m10tls2 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM msdb.dbo.sysjobactivity a JOIN msdb.dbo.sysjobs j ON j.job_id = a.job_id WHERE j.name = N'$job'
              AND a.start_execution_date IS NOT NULL AND a.stop_execution_date IS NULL AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)" | tr -d '[:space:]')" = 0 ] && break
        sleep 1
    done
    q m10tls2 -Q "SET NOCOUNT ON; EXEC msdb.dbo.sp_start_job @job_name = N'$job';" > /dev/null
    for i in $(seq 1 90); do
        [ "$(q m10tls1 -h -1 -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE program_name LIKE N'Repl-LogReader-%'" | tr -d '[:space:]')" = 1 ] && break
        sleep 1
    done
    for h in m10tls1 m10tls2; do
        q $h -h -1 -Q "SET NOCOUNT ON; SELECT CONCAT(N'$h  ', s.login_name, N'  encrypt_option ', c.encrypt_option)
            FROM sys.dm_exec_sessions s JOIN sys.dm_exec_connections c ON c.session_id = s.session_id WHERE s.program_name LIKE N'Repl-LogReader-%';"
    done | sed '/^$/d'
}
echo "-- default"
encryption ""
for l in 2 4; do echo "-- -EncryptionLevel $l"; encryption $l; done
q m10tls2 -d distribution -Q "SET NOCOUNT ON; SELECT TOP (1) runstatus, LEFT(comments, 80) AS comments FROM dbo.MSlogreader_history ORDER BY time DESC, timestamp DESC;"

echo
echo "== The throwaway containers removed"
for h in m10tls1 m10tls2; do
    q $h -Q "SHUTDOWN WITH NOWAIT" > /dev/null 2>&1 || true
    $engine rm -f $h > /dev/null && echo "$h removed"
done
$engine network rm m10tls-net > /dev/null && echo "m10tls-net removed"
