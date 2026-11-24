<#
Pushes a completion notification to @jimb's phone via Pushover when a Copilot turn has run
long enough to be worth interrupting him for.

Two modes:
  -Stamp                     record the turn start time, then exit
  -Title/-Message            send, but only if the stamped turn is at least -ThresholdMinutes old

The threshold is enforced here rather than by the caller's judgement, so the send call can be
made unconditionally at the end of every turn.

Credentials are read from a per-user Windows DPAPI-encrypted file outside this repo.
A missing credential warns and exits 0 so a notification problem can never be mistaken
for a failure of the work itself.
#>
[CmdletBinding(DefaultParameterSetName = 'Send')]
param(
    [Parameter(ParameterSetName = 'Stamp', Mandatory)]
    [switch]$Stamp,

    [Parameter(ParameterSetName = 'Send', Mandatory)]
    [string]$Title,

    [Parameter(ParameterSetName = 'Send', Mandatory)]
    [string]$Message,

    [Parameter(ParameterSetName = 'Send')]
    [double]$ThresholdMinutes = 5,

    [Parameter(ParameterSetName = 'Send')]
    [ValidateRange(-2, 1)]
    [int]$Priority = 0,

    [Parameter(ParameterSetName = 'Send')]
    [switch]$Force,

    [string]$MarkerPath = (Join-Path $env:TEMP 'copilot-turn-start.txt')
)

$ErrorActionPreference = 'Stop'

if ($Stamp) {
    [IO.File]::WriteAllText($MarkerPath, (Get-Date).ToString('o'), (New-Object Text.UTF8Encoding $false))
    Write-Host "turn start stamped: $MarkerPath"
    return
}

$startedAt = $null
if (Test-Path -LiteralPath $MarkerPath) {
    $raw = (Get-Content -LiteralPath $MarkerPath -Raw).Trim()
    $parsed = [datetime]::MinValue
    if ([datetime]::TryParse($raw, [ref]$parsed)) { $startedAt = $parsed }
    Remove-Item -LiteralPath $MarkerPath -Force -ErrorAction SilentlyContinue
}

$elapsed = if ($startedAt) { (Get-Date) - $startedAt } else { [timespan]::Zero }
$elapsedText = if ($elapsed.TotalHours -ge 1) {
    '{0}h {1}m' -f [int]$elapsed.TotalHours, $elapsed.Minutes
}
else {
    '{0:n1} min' -f $elapsed.TotalMinutes
}

if (-not $Force) {
    if (-not $startedAt) {
        Write-Host 'no turn marker found; nothing sent (run with -Stamp at the start of the turn)'
        return
    }
    if ($elapsed.TotalMinutes -lt $ThresholdMinutes) {
        Write-Host ('turn took {0:n1} min, under the {1} min threshold; nothing sent' -f $elapsed.TotalMinutes, $ThresholdMinutes)
        return
    }
}

$credentialPath = Join-Path $env:LOCALAPPDATA 'Copilot\pushover.credential.xml'
if (-not (Test-Path -LiteralPath $credentialPath -PathType Leaf)) {
    Write-Warning "Pushover credential file is missing: $credentialPath"
    return
}
try {
    $credentials = Import-Clixml -LiteralPath $credentialPath
    $userKey = [System.Net.NetworkCredential]::new('', $credentials.user).Password
    $appToken = [System.Net.NetworkCredential]::new('', $credentials.token).Password
}
catch {
    Write-Warning "Pushover credential file could not be read: $($_.Exception.Message)"
    return
}
if ([string]::IsNullOrWhiteSpace($userKey) -or [string]::IsNullOrWhiteSpace($appToken)) {
    Write-Warning 'Pushover credential file is incomplete; notification skipped.'
    return
}

$body = if ($elapsed -gt [timespan]::Zero) { "$Message`n`ntook $elapsedText" } else { $Message }
if ($body.Length -gt 1024) { $body = $body.Substring(0, 1021) + '...' }

$payload = @{
    token    = $appToken
    user     = $userKey
    title    = if ($Title.Length -gt 250) { $Title.Substring(0, 250) } else { $Title }
    message  = $body
    priority = $Priority
}

try {
    $response = Invoke-RestMethod -Method Post -Uri 'https://api.pushover.net/1/messages.json' -Body $payload -TimeoutSec 20
    Write-Host ('pushover sent (status {0}) after {1}' -f $response.status, $elapsedText)
}
catch {
    Write-Warning "Pushover send failed: $($_.Exception.Message)"
}
