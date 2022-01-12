<powershell>
$Fileshare = '${Fileshare_IP}'
$EGIS_HOST = '${EGIS_HOST}'
$VIZ_ENVIRONMENT = '${VIZ_ENVIRONMENT}'
$FIM_VERSION = '${FIM_VERSION}'
$SSH_KEY_CONTENT = '${SSH_KEY_CONTENT}'
$LICENSE_REG_CONTENT = '${LICENSE_REG_CONTENT}'
$WRDS_HOST = '${WRDS_HOST}'
$S3_STATIC_DATA_BUCKET = '${S3_STATIC_DATA_BUCKET}'
$DEPLOY_FILES_PREFIX = '${DEPLOY_FILES_PREFIX}'
$NWM_DATA_BUCKET = '${NWM_DATA_BUCKET}'
$FIM_DATA_BUCKET = '${FIM_DATA_BUCKET}'
$FIM_OUTPUT_BUCKET = '${FIM_OUTPUT_BUCKET}'
$NWM_MAX_FLOWS_DATA_BUCKET = '${NWM_MAX_FLOWS_DATA_BUCKET}'
$RNR_MAX_FLOWS_DATA_BUCKET = '${RNR_MAX_FLOWS_DATA_BUCKET}'
$WINDOWS_SERVICE_STATUS = '${WINDOWS_SERVICE_STATUS}'
$WINDOWS_SERVICE_STARTUP = '${WINDOWS_SERVICE_STARTUP}'
$PIPELINE_USER = '${PIPELINE_USER}'
$PIPELINE_USER_ACCOUNT_PASSWORD = '${PIPELINE_USER_ACCOUNT_PASSWORD}'

$HYDROVIS_EGIS_USER = "hydrovis.proc"
$HYDROVIS_EGIS_PASS = '${HYDROVIS_EGIS_PASS}'

$LOGSTASH_IP = '${LOGSTASH_IP}'
$VLAB_REPO_PREFIX   = '${VLAB_REPO_PREFIX}'
$VLAB_HOST   = '${VLAB_HOST}'

Write-Host "Setting up $PIPELINE_USER profile"
Add-LocalGroupMember -Group "Administrators" -Member $PIPELINE_USER
# This command will fail but that is on purpose. It will initialize the profile which is what we want
$securePassword = ConvertTo-SecureString $PIPELINE_USER_ACCOUNT_PASSWORD -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential $PIPELINE_USER, $securePassword
Start-Process program.exe -Credential $credential

$Logfile = "C:\Users\$PIPELINE_USER\Desktop\pipeline_setup.log"

function LogWrite
{
Param ([string]$logstring)
Write-Host $logstring
$currentdate = Get-Date -Format "MM/dd/yyyy HH:mm K"
$logstring =  $currentdate + ": " +  $logstring
Add-content $Logfile -value $logstring
}

function CreateUTF8File
{
  Param ([string]$file_content, [string]$file_dir, [string]$file_name)

  Set-Location -Path $file_dir
  $file_path = $file_dir + "\" + $file_name
  $file_content | Out-File -Encoding ascii -FilePath $file_path
  Get-ChildItem $file_name | ForEach-Object {
    # get the contents and replace line breaks by U+000A
    $contents = [IO.File]::ReadAllText($_) -replace "`r`n?", "`n"
    # create UTF-8 encoding without signature
    $utf8 = New-Object System.Text.UTF8Encoding $false
    # write the text back
    [IO.File]::WriteAllText($_, $contents, $utf8)
  }
}

LogWrite "Setting up file variables"
$StaticDir = "D:\static"
$DynamicDir = "D:\dynamic"

$AUTHORITATIVE_ROOT = "$StaticDir\authoritative"
$CACHE_ROOT = "$DynamicDir\cache"
$FLAGS_ROOT = "s3://$FIM_OUTPUT_BUCKET/published_flags"
$PRISTINE_ROOT = "$StaticDir\pristine"
$PRO_PROJECT_ROOT = "$StaticDir\pro_project"
$PUBLISHED_ROOT = "$Fileshare\viz\published"
$WORKSPACE_ROOT = "$DynamicDir\authoritative"
$PIPELINE_WORKSPACE = "D:\pipeline_workspace"

LogWrite "Setting up D drive"
Initialize-Disk -Number 1 -PartitionStyle MBR
New-Partition -DiskNumber 1 -UseMaximumSize -IsActive -DriveLetter D
Format-Volume -DriveLetter D -FileSystem NTFS -Confirm:$False

LogWrite "ADDING SSH Files"
$HV_SSH_DIR = "C:\Users\$PIPELINE_USER\.ssh"
$UD_SSH_DIR = "$HOME\.ssh"

LogWrite "Opening Firewall for ArcgisPro License Connection"
New-NetFirewallRule -DisplayName "ArcGISPro License Manager Connection" -Direction "Outbound" -Program "$env:ProgramFiles\ArcGIS\Pro\bin\ArcGISPro.exe" -Action "Allow"

LogWrite "ADDING ArcGIS Pro License Registry"
$HV_LICENSE = "C:\Users\$PIPELINE_USER\Documents\licensed_pro.reg"
$LICENSE_REG_CONTENT | Out-File  $HV_LICENSE

$UD_LICENSE_REG_CONTENT = $LICENSE_REG_CONTENT.Replace("[HKEY_USERS\$PIPELINE_USER\", "[HKEY_CURRENT_USER\")
$UD_LICENSE = "$env:TEMP\ud_pro_license.reg"
$UD_LICENSE_REG_CONTENT | Out-File $UD_LICENSE

Get-Command reg
reg load "HKU\$PIPELINE_USER" "C:\Users\$PIPELINE_USER\ntuser.dat"
reg import $HV_LICENSE
reg import $UD_LICENSE
[gc]::Collect()
reg unload "HKU\$PIPELINE_USER"

New-Item -ItemType Directory -Force -Path $HV_SSH_DIR | Out-Null
CreateUTF8File $SSH_KEY_CONTENT $HV_SSH_DIR id_rsa
"call ssh-keyscan -p 29418 -H $VLAB_HOST >> C:\Users\$PIPELINE_USER\.ssh\known_hosts" | Out-File -Encoding ascii -FilePath "C:\Users\$PIPELINE_USER\Desktop\hv_keyscan.bat"
& "C:\Users\$PIPELINE_USER\Desktop\hv_keyscan.bat"

New-Item -ItemType Directory -Force -Path $UD_SSH_DIR | Out-Null
CreateUTF8File $SSH_KEY_CONTENT $UD_SSH_DIR id_rsa
"call ssh-keyscan -p 29418 -H $VLAB_HOST >> $HOME\.ssh\known_hosts" | Out-File -Encoding ascii -FilePath "C:\Users\$PIPELINE_USER\Desktop\ud_keyscan.bat"
& "C:\Users\$PIPELINE_USER\Desktop\ud_keyscan.bat"

LogWrite "Setting up file structure of static and dynamic data"
New-Item -ItemType Directory -Force -Path $AUTHORITATIVE_ROOT | Out-Null
[Environment]::SetEnvironmentVariable("AUTHORITATIVE_ROOT", $AUTHORITATIVE_ROOT, "2")

New-Item -ItemType Directory -Force -Path $CACHE_ROOT | Out-Null
[Environment]::SetEnvironmentVariable("CACHE_ROOT", $CACHE_ROOT, "2")

[Environment]::SetEnvironmentVariable("FLAGS_ROOT", $FLAGS_ROOT, "2")

New-Item -ItemType Directory -Force -Path $PRISTINE_ROOT | Out-Null
[Environment]::SetEnvironmentVariable("PRISTINE_ROOT", $PRISTINE_ROOT, "2")

New-Item -ItemType Directory -Force -Path $PRO_PROJECT_ROOT | Out-Null
[Environment]::SetEnvironmentVariable("PRO_PROJECT_ROOT", $PRO_PROJECT_ROOT, "2")

[Environment]::SetEnvironmentVariable("PUBLISHED_ROOT", $PUBLISHED_ROOT, "2")

New-Item -ItemType Directory -Force -Path $WORKSPACE_ROOT | Out-Null
[Environment]::SetEnvironmentVariable("WORKSPACE_ROOT", $WORKSPACE_ROOT, "2")

New-Item -ItemType Directory -Force -Path $PIPELINE_WORKSPACE | Out-Null
[Environment]::SetEnvironmentVariable("PIPELINE_WORKSPACE", $PIPELINE_WORKSPACE, "2")

LogWrite "Setting up environment variables"
[Environment]::SetEnvironmentVariable("CACHE_DAYS", "3", "2")
[Environment]::SetEnvironmentVariable("EGIS_HOST", $EGIS_HOST, "2")
[Environment]::SetEnvironmentVariable("EGIS_USERNAME", $HYDROVIS_EGIS_USER, "2")
[Environment]::SetEnvironmentVariable("EGIS_PASSWORD", $HYDROVIS_EGIS_PASS, "2")
[Environment]::SetEnvironmentVariable("FIM_VERSION", $FIM_VERSION, "2")
[Environment]::SetEnvironmentVariable("IMAGE_SERVER", "image", "2")
[Environment]::SetEnvironmentVariable("PRIMARY_SERVER", "server", "2")
[Environment]::SetEnvironmentVariable("VIZ_ENVIRONMENT", $VIZ_ENVIRONMENT, "2")
[Environment]::SetEnvironmentVariable("WRDS_HOST", $WRDS_HOST, "2")
[Environment]::SetEnvironmentVariable("VIZ_USER", $PIPELINE_USER, "2")
[Environment]::SetEnvironmentVariable("NWM_MAX_FLOWS_DATA_BUCKET", $NWM_MAX_FLOWS_DATA_BUCKET, "2")
[Environment]::SetEnvironmentVariable("RNR_MAX_FLOWS_DATA_BUCKET", $RNR_MAX_FLOWS_DATA_BUCKET, "2")
[Environment]::SetEnvironmentVariable("NWM_DATA_BUCKET", $NWM_DATA_BUCKET, "2")
[Environment]::SetEnvironmentVariable("FIM_DATA_BUCKET", $FIM_DATA_BUCKET, "2")
[Environment]::SetEnvironmentVariable("FIM_OUTPUT_BUCKET", $FIM_OUTPUT_BUCKET, "2")
[Environment]::SetEnvironmentVariable("LOGSTASH_SOCKET", "$LOGSTASH_IP`:5000", "2")

function GetRepo
{
   Param ([string]$branch, [string]$repo)

   if (Test-Path -Path $repo) {
       Remove-Item $repo -Recurse
       Get-ChildItem $repo -Hidden -Recurse | Remove-Item -Force -Recurse
   }
   git clone -b $branch $VLAB_REPO_PREFIX/$repo

   if ($LASTEXITCODE -gt 0) { throw "Error occurred getting " + $repo }
}

function Retry([Action]$action)
{
    $attempts=3
    $sleepInSeconds=10
    do
    {
        try
        {
            $action.Invoke();
            $message = "Successfully cloned " + $repo
            LogWrite $message
            break;
        }
        catch [Exception]
        {
            LogWrite $_.Exception.Message
        }
        $attempts--
        if ($attempts -gt 0) {
            $message = "Error: " + $attempts + " attempts left for getting " + $repo
            LogWrite $message
            Start-Sleep $sleepInSeconds
        } else {
            $message = "Error: Attempt limit reached while cloning " + $repo
            throw $message
        }
    } while ($attempts -gt 0)
}

LogWrite "Setting up viz pipeline"

LogWrite "Creating viz file structure"
$VIZ_DIR = "C:\Users\$PIPELINE_USER\NWC\viz"
New-Item -ItemType Directory -Force -Path $VIZ_DIR | Out-Null

Set-Location -Path $VIZ_DIR
LogWrite "CLONING PIPELINE REPOSITORY INTO viz DIRECTORY"
Retry({GetRepo master owp-viz-proc-pipeline})

LogWrite "CLONING VIZ SERVICES REPOSITORY INTO viz DIRECTORY"
$AWS_VIZ_ENVIRONMENT = "aws-" + $VIZ_ENVIRONMENT
Retry({GetRepo $AWS_VIZ_ENVIRONMENT owp-viz-services})

LogWrite "CLONING AWS VIZ SERVICES REPOSITORY INTO viz DIRECTORY"
Retry({GetRepo $VIZ_ENVIRONMENT owp-viz-services-aws})

LogWrite "CREATING FRESH viz VIRTUAL ENVIRONMENT"
& "C:\Program Files\ArcGIS\Pro\bin\Python\Scripts\conda.exe" create -y --name viz --clone arcgispro-py3

LogWrite "ACTIVATING viz VIRTUAL ENVIRONMENT"
& "C:\Program Files\ArcGIS\Pro\bin\Python\Scripts\activate.bat" viz

$window_python_exe = "C:\Program Files\ArcGIS\Pro\bin\Python\envs\viz\python.exe"
$user_python_exe = "C:\Users\$PIPELINE_USER\AppData\Local\ESRI\conda\envs\viz\python.exe"
if (Test-Path -Path $window_python_exe -PathType Leaf) {
    $python_exe = $window_python_exe
} else {
    $python_exe = $user_python_exe
}

LogWrite "INSTALLING PROCESSING PIPELINE REPO"
$PIPELINE_REPO = $VIZ_DIR + "\owp-viz-proc-pipeline"
Set-Location -Path $PIPELINE_REPO
& $python_exe setup.py develop

LogWrite "INSTALLING SERVICE REPO"
$SERVICE_REPO = $VIZ_DIR + "\owp-viz-services"
Set-Location -Path $SERVICE_REPO
& $python_exe setup.py develop
& "C:\Program Files\ArcGIS\Pro\bin\Python\Scripts\conda.exe" install -y -n viz -c esri arcgis

LogWrite "INSTALLING AWS SERVICE REPO"
$AWS_SERVICE_REPO = $VIZ_DIR + "\owp-viz-services-aws"
Set-Location -Path $AWS_SERVICE_REPO
& $python_exe setup.py develop

LogWrite "-->TRANFERRING AUTHORITATIVE DATA"
$s3_authoritative = "s3://" + $S3_STATIC_DATA_BUCKET + "/" + $DEPLOY_FILES_PREFIX + "authoritative_data/"
aws s3 cp $s3_authoritative $AUTHORITATIVE_ROOT --recursive

LogWrite "-->TRANFERRING PRISTINE DATA"
$s3_pristine = "s3://" + $S3_STATIC_DATA_BUCKET + "/" + $DEPLOY_FILES_PREFIX + "pristine_data/"
aws s3 cp $s3_pristine $PRISTINE_ROOT --recursive

LogWrite "-->TRANFERRING PRO PROJECT DATA"
$s3_pro_projects = "s3://" + $S3_STATIC_DATA_BUCKET + "/" + $DEPLOY_FILES_PREFIX + "pro_project_data/"
aws s3 cp $s3_pro_projects $PRO_PROJECT_ROOT --recursive

LogWrite "CREATING CONNECTION FILES FOR $FIM_DATA_BUCKET"
Set-Location -Path $VIZ_DIR
$env:AUTHORITATIVE_ROOT = $AUTHORITATIVE_ROOT
$env:FIM_OUTPUT_BUCKET = $FIM_OUTPUT_BUCKET
& "C:\Program Files\ArcGIS\Pro\bin\Python\envs\viz\python.exe" .\owp-viz-services-aws\aws_loosa\ec2\deploy\create_s3_connection_files.py

Set-Location HKCU:\Software\ESRI\ArcGISPro
Remove-Item -Recurse -Force -Confirm:$false Licensing

LogWrite "UPDATING PYTHON PERMISSIONS FOR $PIPELINE_USER"
$ACL = Get-ACL -Path "C:\Program Files\ArcGIS\Pro\bin\Python"
$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("everyone","FullControl", "Allow")
$ACL.SetAccessRule($AccessRule)
$ACL | Set-Acl -Path "C:\Program Files\ArcGIS\Pro\bin\Python"

LogWrite "UPDATING WORKSPACE PERMISSIONS FOR $PIPELINE_USER"
$ACL = Get-ACL -Path "D:\"
$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("everyone","FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$ACL.SetAccessRule($AccessRule)
$ACL | Set-Acl -Path "D:\"

LogWrite "ADDING $PUBLISHED_ROOT TO $EGIS_HOST"
Set-Location -Path $VIZ_DIR
& "C:\Program Files\ArcGIS\Pro\bin\Python\envs\viz\python.exe" .\owp-viz-services-aws\aws_loosa\ec2\deploy\update_data_stores.py $EGIS_HOST $PUBLISHED_ROOT $HYDROVIS_EGIS_USER $HYDROVIS_EGIS_PASS

LogWrite "DELETING PUBLISHED FLAGS IF THEY EXIST"
$EXISTING_PUBLISHED_FLAGS = aws s3 ls $FLAGS_ROOT
if ($EXISTING_PUBLISHED_FLAGS) {
    LogWrite "DELETING PUBLISHED FLAGS"
    aws s3 rm $FLAGS_ROOT --recursive
}

LogWrite "GETTING NSSM"
New-Item -ItemType Directory -Force -Path 'C:\Programs' | Out-Null
Set-Location -Path 'C:\Programs'
Invoke-WebRequest https://nssm.cc/release/nssm-2.24.zip -OutFile nssm-2.24.zip
Expand-Archive -LiteralPath 'nssm-2.24.zip' -DestinationPath nssm-2.24
Copy-Item .\nssm-2.24\nssm-2.24\win64\nssm.exe 'C:\Programs\nssm.exe'
Remove-Item nssm-2.24.zip
Remove-Item nssm-2.24 -Force -Recurse
$PATH = [Environment]::GetEnvironmentVariable("PATH")
$PATH += ";C:\Programs"
[Environment]::SetEnvironmentVariable("PATH", $PATH, "2")

LogWrite "SETTING UP WINDOWS SERVICES"
Set-Location -Path $VIZ_DIR
& .\owp-viz-services-aws\aws_loosa\ec2\deploy\create_windows_services.ps1 $WINDOWS_SERVICE_STARTUP $WINDOWS_SERVICE_STATUS $PIPELINE_USER $PIPELINE_USER_ACCOUNT_PASSWORD

LogWrite "DONE SETTING UP PIPELINE"
</powershell>
<persist>false</persist>
