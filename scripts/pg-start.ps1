# Start the local PostgreSQL 18 instance for this project.
#
# This runs as a user process, not a Windows service, so it does not survive
# a reboot - run this again after restarting. It listens on 5433 because
# port 5432 is taken by a pre-existing PostgreSQL 17 service, which this
# never touches.

$bin  = "$env:LOCALAPPDATA\Programs\PostgreSQL18\pgsql\bin"
$data = "C:\pgdata\epl"
$log  = "C:\pgdata\epl.log"

if (-not (Test-Path $data)) {
    Write-Error "No data directory at $data. See README.md for first-time setup."
    exit 1
}

& "$bin\pg_ctl.exe" -D $data status 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Output "Already running."
} else {
    & "$bin\pg_ctl.exe" -D $data -l $log -o "-p 5433" start
}

& "$bin\pg_ctl.exe" -D $data status
