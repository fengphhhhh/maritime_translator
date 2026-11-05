$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = Split-Path -Parent $PSScriptRoot
$modelDirectory = Join-Path $projectRoot 'assets/models'
$models = @(
    @{
        Repository = 'ggerganov/whisper.cpp'
        Revision = '5359861c739e955e79d9a303bcbc70fb988958b1'
        File = 'ggml-large-v3-turbo-q5_0.bin'
        Bytes = 574041195
        Sha256 = '394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2'
    },
    @{
        Repository = 'Qwen/Qwen2.5-1.5B-Instruct-GGUF'
        Revision = '91cad51170dc346986eccefdc2dd33a9da36ead9'
        File = 'qwen2.5-1.5b-instruct-q4_k_m.gguf'
        Bytes = 1117320736
        Sha256 = '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e'
    }
)
New-Item -ItemType Directory -Path $modelDirectory -Force | Out-Null
foreach ($model in $models) {
    $destination = Join-Path $modelDirectory $model.File
    if ((Test-Path -LiteralPath $destination) -and
        (Get-Item -LiteralPath $destination).Length -eq $model.Bytes -and
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $model.Sha256) {
        Write-Output "Verified existing model: $($model.File)"
        continue
    }
    $partial = "$destination.download"
    $uri = "https://huggingface.co/$($model.Repository)/resolve/$($model.Revision)/$($model.File)"
    Write-Output "Downloading $($model.File) ($($model.Bytes) bytes)..."
    Invoke-WebRequest -Uri $uri -OutFile $partial -TimeoutSec 900
    if ((Get-Item -LiteralPath $partial).Length -ne $model.Bytes -or
        (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $model.Sha256) {
        throw "Model integrity check failed: $($model.File). The partial file was not installed."
    }
    Move-Item -LiteralPath $partial -Destination $destination -Force
    Write-Output "Verified SHA-256 and installed: $($model.File)"
}
