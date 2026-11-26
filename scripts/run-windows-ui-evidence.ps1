param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("success", "conflict")]
    [string]$Scenario,

    [Parameter(Mandatory = $true)]
    [string]$EvidenceDir
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$appDir = Join-Path $repoRoot "crates/kshift-windows-gpui"
$appExe = Join-Path $appDir "target/release/kshift-windows-gpui.exe"
$mockExe = Join-Path $repoRoot "target/release/examples/mock_server.exe"
$cert = Join-Path $repoRoot "fixtures/tls/server.pem"
$key = Join-Path $repoRoot "fixtures/tls/server-key.pem"
$ca = Join-Path $repoRoot "fixtures/tls/ca.pem"
$readyFile = Join-Path $EvidenceDir "mock-server-ready.txt"

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
$mockArgs = @("--cert", $cert, "--key", $key, "--ready-file", $readyFile)
if ($Scenario -eq "conflict") {
    $mockArgs += "--conflict-on-update"
}

$mock = Start-Process -FilePath $mockExe `
    -ArgumentList $mockArgs `
    -RedirectStandardOutput (Join-Path $EvidenceDir "mock-server.log") `
    -RedirectStandardError (Join-Path $EvidenceDir "mock-server.err.log") `
    -PassThru `
    -NoNewWindow

try {
    $ready = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        if (Test-Path $readyFile) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        throw "mock TLS server did not become ready"
    }

    $env:KSHIFT_ENDPOINT = (Get-Content $readyFile -Raw).Trim()
    $env:KSHIFT_CA_PEM = $ca
    $env:KSHIFT_TOKEN = "smoke-token"
    $env:KSHIFT_PROJECT_ID = "11111111-2222-4333-8444-555555555555"
    $env:KSHIFT_TLS_DOMAIN = "localhost"
    $env:KSHIFT_SMOKE_EDIT = "1"
    $env:KSHIFT_SMOKE_SECONDS = "8"

    $appLog = Join-Path $EvidenceDir "app.log"
    $appErrLog = Join-Path $EvidenceDir "app.err.log"
    $app = Start-Process -FilePath $appExe `
        -WorkingDirectory $appDir `
        -ArgumentList @("--today", "2026-11-13", "--open-task", "aaaaaaaa-0000-4000-8000-000000000001") `
        -RedirectStandardOutput $appLog `
        -RedirectStandardError $appErrLog `
        -PassThru `
        -NoNewWindow

    $app | Wait-Process -Timeout 20
    if (-not $app.HasExited) {
        throw "Windows app did not exit after smoke timeout"
    }

    $log = Get-Content $appLog -Raw
    if ($Scenario -eq "success") {
        if ($log -notmatch "save committed") {
            throw "successful-save evidence was not emitted"
        }
    } else {
        if ($log -notmatch "save conflict") {
            throw "conflict evidence was not emitted"
        }
        if ($log -notmatch "draft_preserved=true") {
            throw "conflict evidence did not confirm draft preservation"
        }
    }
} finally {
    if ($mock -and -not $mock.HasExited) {
        $mock.Kill()
    }
}
