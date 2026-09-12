# Stop the local PostgreSQL 18 instance for this project.
# Leaves the unrelated PostgreSQL 17 service on 5432 alone.

$bin  = "$env:LOCALAPPDATA\Programs\PostgreSQL18\pgsql\bin"
$data = "C:\pgdata\epl"

& "$bin\pg_ctl.exe" -D $data -m fast stop
