<powershell>
New-Item -Path "C:\" -Name "Monitor" -ItemType "directory"
Copy-S3Object -Bucket 'hydrovis-${environment}-egis-${region}' -Key 'software/Monitor/MonitorDeploy.zip' -LocalFile 'C:\Monitor\MonitorDeploy.zip'
Copy-S3Object -Bucket 'hydrovis-${environment}-egis-${region}' -Key 'installs/software/licenses/10_8_1/ArcGISMonitor_ArcGISServer_1028623.prvc' -LocalFile 'C:\Monitor\ArcGISMonitor_ArcGISServer_1028623.prvc'
cd C:\Monitor
Expand-Archive -Path "C:\Monitor\MonitorDeploy.zip"  -DestinationPath "C:\Monitor"
Initialize-Disk -Number 1 -PartitionStyle MBR 
New-Partition -DiskNumber 1 -UseMaximumSize -IsActive -DriveLetter D
Format-Volume -DriveLetter D -FileSystem NTFS
New-Item -Path "D:\" -Name "Temp" -ItemType "directory"
#Copy-S3Object -Bucket 'hydrovis-${environment}-egis-${region}' -Key 'software/Monitor/MonitorDeploy.zip' -LocalFile 'C:\Monitor\MonitorDeploy.zip'
#Read-S3Object -Bucket 'hydrovis-${environment}-egis-${region}' -KeyPrefix 'software/Monitor' -Folder "C:\Monitor" 
start-process "cmd.exe" "/c C:\Monitor\setupMonitor.bat"
Start-Sleep 1200
Start-Process "cmd.exe" "/c C:\Monitor\setupMonitor2.bat"
</powershell>
