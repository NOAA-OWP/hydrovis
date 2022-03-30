<powershell>
$PIPELINE_USER = '${PIPELINE_USER}'

Initialize-Disk -Number 1 -PartitionStyle MBR
New-Partition -DiskNumber 1 -UseMaximumSize -IsActive -DriveLetter D
Format-Volume -DriveLetter D -FileSystem NTFS -Confirm:$False

New-Item -ItemType Directory -Force -Path D:\viz | Out-Null
New-Item -ItemType Directory -Force -Path D:\viz\published | Out-Null

Add-LocalGroupMember -Group "Administrators" -Member $PIPELINE_USER

New-SmbShare -Name "viz" -Path "D:\viz" -FullAccess $PIPELINE_USER

</powershell>
