﻿Add-PsSnapin VMware.VimAutomation.Core -ea "SilentlyContinue" -Verbose
Add-pssnapin Microsoft.Exchange.Management.PowerShell.E2010
 
$EndPoint = '10.21.8.17'
$MailboxDbVol = 'Barkz-Ex13-Db-01'
$Datastore = 'Barkz-Datastore-1'
$MailboxDbVolSnapSuffix = 'MANUAL-05'
$HostGroupName = 'Barkz-SJ-vCenter'
$vCenter = '10.21.8.11'
$VMHost = '10.21.8.31'
$VM = 'Exchange 2013'
$MailboxServer = 'EX13-1.csglab.purestorage.com'
 
$FlashArray = New-PfaArray -EndPoint $EndPoint -Credentials(Get-Credential) -IgnoreCertificateError
 
#region Provision new volume and new mailbox database.
$VolName = Read-Host "Name of the volume to create?"
$VolSize = Read-Host "Size of $VolName in TB?"
$Serial = New-PfaVolume -Array $FlashArray -VolumeName $VolName -Unit TB -Size $VolSize | Select serial
New-PfaHostGroupVolumeConnection -Array $FlashArray -VolumeName $VolName -HostGroupName $HostGroupName

$vCenterAdmin = Read-Host "vCenter Administrator"
Connect-ViServer -Server $vCenter -User $vCenterAdmin -Password (Get-Credential) | Out-Null
Get-VMHostStorage -VMHost $VMHost  -RescanAllHba -RescanVmfs | Out-Null
$CanonicalName = "naa.624a9370" + ($Serial.serial).ToLower()
Get-ScsiLun -vmhost $VMHost -CanonicalName $CanonicalName
$DeviceName = "/vmfs/devices/disks/naa.624a9370" + ($Serial.serial).ToLower()
New-HardDisk -VM $VM -DiskType rawPhysical -DeviceName $DeviceName
Disconnect-VIServer  -Server $vCenter -Force -Confirm:$false | Out-Null
 
$NewPartition = (Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' } | Select Number).Number
Initialize-Disk -Number $NewPartition
$Drive = New-Partition -DiskNumber $NewPartition -UseMaximumSize -AssignDriveLetter | Select DriveLetter
Format-Volume -DriveLetter $Drive.DriveLetter -Confirm:$false -Force
 
New-MailboxDatabase -Name $VolName -Server $MailboxServer -EdbFilePath "F:\$VolName\$VolName.edb" -LogFolderPath 'F:\Logs'
Restart-Service -Name MSExchangeIS -Force
Get-MailboxDatabase
#endregion
 
#region Create snapshot and mount for recovery use.
New-PfaVolumeSnapshots -Array $FlashArray -Sources $MailboxDbVol -Suffix $MailboxDbVolSnapSuffix
$Serial = New-PfaVolume -Array $FlashArray -Source "$MailboxDbVol.$MailboxDbVolSnapSuffix" -VolumeName "Mailbox-SMBR-$MailboxDbVolSnapSuffix" | Select serial
New-PfaHostGroupVolumeConnection -Array $FlashArray -VolumeName "Mailbox-SMBR-$MailboxDbVolSnapSuffix" -HostGroupName $HostGroupName
 
$vCenterAdmin = Read-Host "vCenter Administrator"
Connect-ViServer -Server $vCenter -User $vCenterAdmin -Password (Get-Credential) | Out-Null
Get-VMHostStorage -VMHost $VMHost  -RescanAllHba -RescanVmfs | Out-Null
$CanonicalName = "naa.624a9370" + ($Serial.serial).ToLower()
Get-ScsiLun -vmhost $VMHost -CanonicalName $CanonicalName
$DeviceName = "/vmfs/devices/disks/naa.624a9370" + ($Serial.serial).ToLower()
New-HardDisk -VM $VM -DiskType rawPhysical -DeviceName $DeviceName
Disconnect-VIServer  -Server $vCenter -Force -Confirm:$false | Out-Null
 
$NewHD = Get-Disk | Where-Object { $_.OperationalStatus -eq 'Offline' } | Select Number
Set-Disk -Number $NewHD.Number -IsOffline:$false
#endregion
 
#region Restore mailbox database from snapshot.
Get-MailboxDatabase
$MailboxDb = (Get-MailboxDatabase).Name
Get-MailboxDatabaseCopyStatus -Identity $MailboxDb
Dismount-Database $MailboxDb
Get-Disk -Number 1
Set-Disk -Number 1 -IsOffline:$true
Get-PfaVolumeSnapshots -Array $FlashArray -VolumeName $MailboxDbVol | Select name, created | Format-Table -AutoSize
$snapshotsource = Read-Host "Which snapshot do you want to restore? "
New-PfaVolume -Array $FlashArray -Source $snapshotsource -VolumeName $MailboxDbVol -Overwrite
Set-Disk -Number 1 -IsOffline:$false
Mount-Database -Identity $MailboxDb
Get-MailboxDatabaseCopyStatus -Identity $MailboxDb
#endregion

# SIG # Begin signature block
# MIITTgYJKoZIhvcNAQcCoIITPzCCEzsCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQUgVAPLGnMC39xn0b88GQVnOdj
# YxSggg3qMIIEFDCCAvygAwIBAgILBAAAAAABL07hUtcwDQYJKoZIhvcNAQEFBQAw
# VzELMAkGA1UEBhMCQkUxGTAXBgNVBAoTEEdsb2JhbFNpZ24gbnYtc2ExEDAOBgNV
# BAsTB1Jvb3QgQ0ExGzAZBgNVBAMTEkdsb2JhbFNpZ24gUm9vdCBDQTAeFw0xMTA0
# MTMxMDAwMDBaFw0yODAxMjgxMjAwMDBaMFIxCzAJBgNVBAYTAkJFMRkwFwYDVQQK
# ExBHbG9iYWxTaWduIG52LXNhMSgwJgYDVQQDEx9HbG9iYWxTaWduIFRpbWVzdGFt
# cGluZyBDQSAtIEcyMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAlO9l
# +LVXn6BTDTQG6wkft0cYasvwW+T/J6U00feJGr+esc0SQW5m1IGghYtkWkYvmaCN
# d7HivFzdItdqZ9C76Mp03otPDbBS5ZBb60cO8eefnAuQZT4XljBFcm05oRc2yrmg
# jBtPCBn2gTGtYRakYua0QJ7D/PuV9vu1LpWBmODvxevYAll4d/eq41JrUJEpxfz3
# zZNl0mBhIvIG+zLdFlH6Dv2KMPAXCae78wSuq5DnbN96qfTvxGInX2+ZbTh0qhGL
# 2t/HFEzphbLswn1KJo/nVrqm4M+SU4B09APsaLJgvIQgAIMboe60dAXBKY5i0Eex
# +vBTzBj5Ljv5cH60JQIDAQABo4HlMIHiMA4GA1UdDwEB/wQEAwIBBjASBgNVHRMB
# Af8ECDAGAQH/AgEAMB0GA1UdDgQWBBRG2D7/3OO+/4Pm9IWbsN1q1hSpwTBHBgNV
# HSAEQDA+MDwGBFUdIAAwNDAyBggrBgEFBQcCARYmaHR0cHM6Ly93d3cuZ2xvYmFs
# c2lnbi5jb20vcmVwb3NpdG9yeS8wMwYDVR0fBCwwKjAooCagJIYiaHR0cDovL2Ny
# bC5nbG9iYWxzaWduLm5ldC9yb290LmNybDAfBgNVHSMEGDAWgBRge2YaRQ2XyolQ
# L30EzTSo//z9SzANBgkqhkiG9w0BAQUFAAOCAQEATl5WkB5GtNlJMfO7FzkoG8IW
# 3f1B3AkFBJtvsqKa1pkuQJkAVbXqP6UgdtOGNNQXzFU6x4Lu76i6vNgGnxVQ380W
# e1I6AtcZGv2v8Hhc4EvFGN86JB7arLipWAQCBzDbsBJe/jG+8ARI9PBw+DpeVoPP
# PfsNvPTF7ZedudTbpSeE4zibi6c1hkQgpDttpGoLoYP9KOva7yj2zIhd+wo7AKvg
# IeviLzVsD440RZfroveZMzV+y5qKu0VN5z+fwtmK+mWybsd+Zf/okuEsMaL3sCc2
# SI8mbzvuTXYfecPlf5Y1vC0OzAGwjn//UYCAp5LUs0RGZIyHTxZjBzFLY7Df8zCC
# BJ8wggOHoAMCAQICEhEhBqCB0z/YeuWCTMFrUglOAzANBgkqhkiG9w0BAQUFADBS
# MQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1zYTEoMCYGA1UE
# AxMfR2xvYmFsU2lnbiBUaW1lc3RhbXBpbmcgQ0EgLSBHMjAeFw0xNTAyMDMwMDAw
# MDBaFw0yNjAzMDMwMDAwMDBaMGAxCzAJBgNVBAYTAlNHMR8wHQYDVQQKExZHTU8g
# R2xvYmFsU2lnbiBQdGUgTHRkMTAwLgYDVQQDEydHbG9iYWxTaWduIFRTQSBmb3Ig
# TVMgQXV0aGVudGljb2RlIC0gRzIwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEK
# AoIBAQCwF66i07YEMFYeWA+x7VWk1lTL2PZzOuxdXqsl/Tal+oTDYUDFRrVZUjtC
# oi5fE2IQqVvmc9aSJbF9I+MGs4c6DkPw1wCJU6IRMVIobl1AcjzyCXenSZKX1GyQ
# oHan/bjcs53yB2AsT1iYAGvTFVTg+t3/gCxfGKaY/9Sr7KFFWbIub2Jd4NkZrItX
# nKgmK9kXpRDSRwgacCwzi39ogCq1oV1r3Y0CAikDqnw3u7spTj1Tk7Om+o/SWJMV
# TLktq4CjoyX7r/cIZLB6RA9cENdfYTeqTmvT0lMlnYJz+iz5crCpGTkqUPqp0Dw6
# yuhb7/VfUfT5CtmXNd5qheYjBEKvAgMBAAGjggFfMIIBWzAOBgNVHQ8BAf8EBAMC
# B4AwTAYDVR0gBEUwQzBBBgkrBgEEAaAyAR4wNDAyBggrBgEFBQcCARYmaHR0cHM6
# Ly93d3cuZ2xvYmFsc2lnbi5jb20vcmVwb3NpdG9yeS8wCQYDVR0TBAIwADAWBgNV
# HSUBAf8EDDAKBggrBgEFBQcDCDBCBgNVHR8EOzA5MDegNaAzhjFodHRwOi8vY3Js
# Lmdsb2JhbHNpZ24uY29tL2dzL2dzdGltZXN0YW1waW5nZzIuY3JsMFQGCCsGAQUF
# BwEBBEgwRjBEBggrBgEFBQcwAoY4aHR0cDovL3NlY3VyZS5nbG9iYWxzaWduLmNv
# bS9jYWNlcnQvZ3N0aW1lc3RhbXBpbmdnMi5jcnQwHQYDVR0OBBYEFNSihEo4Whh/
# uk8wUL2d1XqH1gn3MB8GA1UdIwQYMBaAFEbYPv/c477/g+b0hZuw3WrWFKnBMA0G
# CSqGSIb3DQEBBQUAA4IBAQCAMtwHjRygnJ08Kug9IYtZoU1+zETOA75+qrzE5ntz
# u0vxiNqQTnU3KDhjudcrD1SpVs53OZcwc82b2dkFRRyNpLgDXU/ZHC6Y4OmI5uzX
# BX5WKnv3FlujrY+XJRKEG7JcY0oK0u8QVEeChDVpKJwM5B8UFiT6ddx0cm5OyuNq
# Q6/PfTZI0b3pBpEsL6bIcf3PvdidIZj8r9veIoyvp/N3753co3BLRBrweIUe8qWM
# ObXciBw37a0U9QcLJr2+bQJesbiwWGyFOg32/1onDMXeU+dUPFZMyU5MMPbyXPsa
# jMKCvq1ZkfYbTVV7z1sB3P16028jXDJHmwHzwVEURoqbMIIFKzCCBBOgAwIBAgIQ
# CamgNd9B0v6RJ4iA0KHDFDANBgkqhkiG9w0BAQsFADByMQswCQYDVQQGEwJVUzEV
# MBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29t
# MTEwLwYDVQQDEyhEaWdpQ2VydCBTSEEyIEFzc3VyZWQgSUQgQ29kZSBTaWduaW5n
# IENBMB4XDTE2MDQyMzAwMDAwMFoXDTE3MDQyNzEyMDAwMFowaDELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCkNhbGlmb3JuaWExFDASBgNVBAcTC1NhbnRhIENsYXJhMRYw
# FAYDVQQKEw1Sb2JlcnQgQmFya2VyMRYwFAYDVQQDEw1Sb2JlcnQgQmFya2VyMIIB
# IjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAr1I0EO2uOScoPi9giUITw4CH
# 1qT2MJsPqG4pHhndW2M12EBl4HcDVi/cOZG+EZHduaKFSXy6nR0BuPbNB76/NODd
# S0id2Q7ppWbtld74O/OmtLn6SAW6qjKeYas7N4xUV6pK62yzGGBG/gr9CS97kzaW
# 6mwR803MmTwTVa9QofV3DioppJM7eTWSmPHUfyGVAE1LjnlYlgKPcAGGmtseXKwQ
# jyXq8wCvlnUOPiHZp/cXPpJzYq6krehZnnEqNLALQROtBEqnKXGFEQH8U0Qc7pqu
# gO+0lhnbV9/XLwIauyjLqNyJ+p7lZ8ZElS17j9PjQuJ+hyXotzPL1WIod9ghXwID
# AQABo4IBxTCCAcEwHwYDVR0jBBgwFoAUWsS5eyoKo6XqcQPAYPkt9mV1DlgwHQYD
# VR0OBBYEFJQeLmdYk4a/RXLk2t9XUgabNd/RMA4GA1UdDwEB/wQEAwIHgDATBgNV
# HSUEDDAKBggrBgEFBQcDAzB3BgNVHR8EcDBuMDWgM6Axhi9odHRwOi8vY3JsMy5k
# aWdpY2VydC5jb20vc2hhMi1hc3N1cmVkLWNzLWcxLmNybDA1oDOgMYYvaHR0cDov
# L2NybDQuZGlnaWNlcnQuY29tL3NoYTItYXNzdXJlZC1jcy1nMS5jcmwwTAYDVR0g
# BEUwQzA3BglghkgBhv1sAwEwKjAoBggrBgEFBQcCARYcaHR0cHM6Ly93d3cuZGln
# aWNlcnQuY29tL0NQUzAIBgZngQwBBAEwgYQGCCsGAQUFBwEBBHgwdjAkBggrBgEF
# BQcwAYYYaHR0cDovL29jc3AuZGlnaWNlcnQuY29tME4GCCsGAQUFBzAChkJodHRw
# Oi8vY2FjZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRTSEEyQXNzdXJlZElEQ29k
# ZVNpZ25pbmdDQS5jcnQwDAYDVR0TAQH/BAIwADANBgkqhkiG9w0BAQsFAAOCAQEA
# K7mB6k0XrieW8Fgc1PE8QmQWhXieDu1TKWAltSgXopddqUyLCdeqMoPj6otYYdnL
# Nf9VGjxCWnZj1qXBrgyYv1FuWgwDhfL/xmZ09uKx9yIjx45HFU1Pw3sQSQHO+Q0p
# p652T7V7pfs9wcsqzUZJpdCRXtWAPpGuYyW+oX3jai6Mco/DrdP6G7WPMnlc/5yV
# 7Y824yXsJKoX/qENgtbctZeQ4htx4aaT3Pg79ppUunl754w8MDAVTQUVrKGH3TDw
# sBTRjsGb7on+QldBJzOsrE2Pq9P4fnIYdqO74JQ5YpUHn2p1pLXSukWchNgIeix/
# yCdjn78jL/RvpsJoSPdKfzGCBM4wggTKAgEBMIGGMHIxCzAJBgNVBAYTAlVTMRUw
# EwYDVQQKEwxEaWdpQ2VydCBJbmMxGTAXBgNVBAsTEHd3dy5kaWdpY2VydC5jb20x
# MTAvBgNVBAMTKERpZ2lDZXJ0IFNIQTIgQXNzdXJlZCBJRCBDb2RlIFNpZ25pbmcg
# Q0ECEAmpoDXfQdL+kSeIgNChwxQwCQYFKw4DAhoFAKB4MBgGCisGAQQBgjcCAQwx
# CjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYKKwYBBAGC
# NwIBCzEOMAwGCisGAQQBgjcCARUwIwYJKoZIhvcNAQkEMRYEFPCa2jHkgEJY4o3z
# +fEZVc0owTdZMA0GCSqGSIb3DQEBAQUABIIBAKBZd998By1sJSWvbt7gjELvkwVv
# vqHHSdHKzOT5eVz9O/ggyvHCeUuqJ3PT3FDvMKSqU04fZJxFoenJCi4faYo7tgVI
# kL1wKu7qTQuziAQaOFxf1UQXaTKR4Kg+KXbl+IKnyX0CTx0Bw0G095weE+isjRc7
# ssMtMfW1yN3L2zPS2ZECKFxwWk4yO0iX5g71HCBMUaeP/3jFppHGWuyz5DMOqGqy
# rj7Tqn2bU9Ba/VkxagPu5lzH+QMJTrHXXzbixYUCTwXKKyu71tK4sb01yUkyRhAD
# 0011/J6Ryjw2UEgkrGcYfimcI1Hcaln/j+jEM1YhOxbauqmOYmTx5qK0kxmhggKi
# MIICngYJKoZIhvcNAQkGMYICjzCCAosCAQEwaDBSMQswCQYDVQQGEwJCRTEZMBcG
# A1UEChMQR2xvYmFsU2lnbiBudi1zYTEoMCYGA1UEAxMfR2xvYmFsU2lnbiBUaW1l
# c3RhbXBpbmcgQ0EgLSBHMgISESEGoIHTP9h65YJMwWtSCU4DMAkGBSsOAwIaBQCg
# gf0wGAYJKoZIhvcNAQkDMQsGCSqGSIb3DQEHATAcBgkqhkiG9w0BCQUxDxcNMTYw
# NjA3MTk0MDE0WjAjBgkqhkiG9w0BCQQxFgQUGuL0RdgPXIujjY0TB99v6VHa7IIw
# gZ0GCyqGSIb3DQEJEAIMMYGNMIGKMIGHMIGEBBSzYwi01M3tT8+9ZrlV+uO/sSwp
# 5jBsMFakVDBSMQswCQYDVQQGEwJCRTEZMBcGA1UEChMQR2xvYmFsU2lnbiBudi1z
# YTEoMCYGA1UEAxMfR2xvYmFsU2lnbiBUaW1lc3RhbXBpbmcgQ0EgLSBHMgISESEG
# oIHTP9h65YJMwWtSCU4DMA0GCSqGSIb3DQEBAQUABIIBABH00zpPcLWQpIskmesK
# NtdC+o2UMAzbhOsAHB8FjjyjiXijKOXuReEFxyVxLrR84K9FHnLCwS2F+A8i5Y+D
# Muq3efVSwRAqATNOPTTMBwIp6mxuB49sqtLc3OLq1mmhL5dPOyHCfMh57LmqS/YQ
# 4j4rHwgPYcXG0WFXEKOCn69B6nnusB4p3rCS+gmyYqAQX2gtKAL2demCllwUoAXt
# p2Hk3iG2a+dQsTbj859hW7wmvg1O+xpgig4Puy1R9yTuqYB+49iWUQUUJ0uJ1SpJ
# fsCWU6pQs66GrL4T5B2LinLQmEMZtXziBj47yvvcA3w/yOctrafg/00tI6pmkBXs
# IWA=
# SIG # End signature block
