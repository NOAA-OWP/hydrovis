param ($SERVICE_STARTUP, $START_SERVICE, $SERVICE_ACCOUNT, $SERVICE_ACCOUNT_PASSWORD)

Install-Module powershell-yaml -Confirm:$False -Force
Import-Module powershell-yaml

function Create_Service {

    param (
        $service_name,
        $python_path,
        $nssm_path,
        $viz_path,
        $service_startup_type,
        $service_start,
        $servce_account_username,
        $service_account_password
    )

    Write-Host "Creating Windows Service for $service_name"
    & $nssm_path install $service_name $python_path
    & $nssm_path set $service_name AppDirectory "$viz_path\aws_loosa\ec2\pipelines"
    & $nssm_path set $service_name AppParameters "$viz_path\aws_loosa\processing_pipeline\run_pipelines.py $viz_path\aws_loosa\ec2\pipelines\$service_name\pipeline.yml"
    & $nssm_path set $service_name DisplayName $service_name
    & $nssm_path set $service_name Description "$viz_path\aws_loosa\ec2\pipelines"
    & $nssm_path set $service_name Start $service_startup_type
    & $nssm_path set $service_name ObjectName ".\$servce_account_username" $service_account_password

    if ($service_start="start") {
       Write-Host "STARTING WINDOWS SERVICES FOR $service_name"
       & $nssm_path start $service_name
    } else {
       Write-Host "STOPPING WINDOWS SERVICES FOR $service_name"
       & $nssm_path stop $service_name
    }
}

function Update_Service {

    param (
        $service_name,
        $python_path,
        $nssm_path,
        $viz_path,
        $service_startup_type,
        $service_start,
        $servce_account_username,
        $service_account_password
    )

    Write-Host "Creating Windows Service for $service_name"
    & $nssm_path set $service_name Application $python_path
    & $nssm_path set $service_name AppDirectory "$viz_path\aws_loosa\ec2\pipelines"
    & $nssm_path set $service_name AppParameters "$viz_path\aws_loosa\processing_pipeline\run_pipelines.py $viz_path\aws_loosa\ec2\pipelines\$service_name\pipeline.yml"
    & $nssm_path set $service_name DisplayName $service_name
    & $nssm_path set $service_name Description "$viz_path\aws_loosa\ec2\pipelines"
    & $nssm_path set $service_name Start $service_startup_type
    & $nssm_path set $service_name ObjectName ".\$servce_account_username" $service_account_password

    if ($service_start="start") {
       Write-Host "STARTING WINDOWS SERVICES FOR $service_name"
       & $nssm_path start $service_name
    } else {
       Write-Host "STOPPING WINDOWS SERVICES FOR $service_name"
       & $nssm_path stop $service_name
    }
}

function Delete_Service {

    param (
        $service_name,
        $nssm_path
    )


    Write-Host "Deleting Windows Service for $service_name"
    & $nssm_path stop $service_name
    & $nssm_path remove $service_name confirm
}

$USER_PYTHON="C:\Users\$SERVICE_ACCOUNT\AppData\Local\ESRI\conda\envs\viz\pythonw.exe"
$SYSTEM_PYTHON="C:\Program Files\ArcGIS\Pro\bin\Python\envs\viz\pythonw.exe"

if (Test-Path -Path $USER_PYTHON) {
    $PYTHONW_PATH=$USER_PYTHON
} elseif (Test-Path -Path $SYSTEM_PYTHON) {
    $PYTHONW_PATH=$SYSTEM_PYTHON
} else {
    throw "Neither $USER_PYTHON or $SYSTEM_PYTHON exist"
} 

$VIZ_DIR="C:\Users\$SERVICE_ACCOUNT\NWC\viz"
$AWS_SERVICE_REPO = $VIZ_DIR + "\hydrovis\Core\VIZ\EC2\code"
$PIPELINES_CONFIG = "$AWS_SERVICE_REPO\aws_loosa\ec2\deploy\pipelines_config.yml"
$NSSM = "C:\Programs\nssm.exe"

Write-Host $PIPELINES_CONFIG

$fileContent = Get-Content $PIPELINES_CONFIG
foreach ($line in $fileContent) { $content = $content + "`n" + $line }
$yaml = ConvertFrom-YAML $content

$TOTAL_PROCESSES=$yaml.ADDED.count

Foreach ($service in $yaml.ADDED) {
  Create_Service -service_name $service -python_path $PYTHONW_PATH -nssm_path $NSSM -viz_path $AWS_SERVICE_REPO -service_startup_type $WINDOWS_SERVICE_STARTUP -service_start $WINDOWS_SERVICE_STATUS -servce_account_username $SERVICE_ACCOUNT -service_account_password $SERVICE_ACCOUNT_PASSWORD
}

Foreach ($service in $yaml.REMOVED) {
  Delete_Service -service_name $service -nssm_path $NSSM
}

Foreach ($service in $yaml.UNCHANGED) {
  Update_Service -service_name $service -python_path $PYTHONW_PATH -nssm_path $NSSM -viz_path $AWS_SERVICE_REPO -service_startup_type $WINDOWS_SERVICE_STARTUP -service_start $WINDOWS_SERVICE_STATUS -servce_account_username $SERVICE_ACCOUNT -service_account_password $SERVICE_ACCOUNT_PASSWORD
}