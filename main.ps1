$ErrorActionPreference="SilentlyContinue"
Stop-Transcript | out-null
$ErrorActionPreference = "Continue"
Start-Transcript -path C:\mait_log.txt -append

$Date = Get-Date
"Maintenance Starting at " + $Date
$User = 'XXXX'
$Password = (Get-Content "\\gearhead\scripts$\Password.txt" | ConvertTo-SecureString)
$Cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password
import-module ActiveDirectory
$ADServers = Get-ADComputer -Filter 'OperatingSystem -like "*windows server*"'
[System.Collections.ArrayList]$WindowsVirtualServers = @()
[System.Collections.ArrayList]$LinuxVirtualServers = @()
[System.Collections.ArrayList]$HyperVServers = @()
ForEach($server in $ADServers) {
     if ($server.DNSHostName -like '*gearhead*' -Or $server.DNSHostName -like '*joker*')  { 
        $HyperVServers.add($server)
     } else {
        $WindowsVirtualServers.add($server) 
     }
} 

#$Date = Get-Date
#"Starting Linux jobs at $Date"

#import-csv \\gearhead\scripts$\linux_servers.csv | foreach {
#  Start-Job -ArgumentList $_.server, $_.username, $_.password -FilePath "\\gearhead\scripts$\linux_mait.ps1"
#}

#Get-Job | Receive-Job
#Get-Job | Wait-Job

$Date = Get-Date
"Starting Windows jobs at $Date"

Foreach($server in $WindowsVirtualServers) {
  Start-Job -ArgumentList $server -FilePath "\\gearhead\scripts$\windows_mait.ps1"
}

$Date = Get-Date
"Waiting for jobs to complete at $Date"

Get-Job | Receive-Job
Get-Job | Wait-Job

$Date = Get-Date
"Jobs completed at $Date, moving on to physical servers."

Enter-PSSession -ComputerName gearhead -Credential $Cred
    ipmo \\gearhead\scripts$\PSWindowsUpdate
    "Running Windows Updates on gearhead..."
    Get-WUInstall -acceptall -IgnoreReboot -IgnoreUserInput 
Exit-PSSession  
ipmo \\gearhead\scripts$\PSWindowsUpdate
"Running Windows Updates on joker..."
Get-WUInstall -acceptall -IgnoreReboot -IgnoreUserInput 

Foreach($server in $HyperVServer) {
  Start-Job -ArgumentList $server -FilePath "\\gearhead\scripts$\vm_snapshot.ps1"
}

$Date = Get-Date
"Rebooting gearhead at " + $Date + " and waiting..."
Restart-Computer -ComputerName gearhead -Wait -Force 
$Date = Get-Date
"Rebooting joker and finishing maintenance at " + $Date
Stop-Transcript
Restart-Computer -ComputerName joker -Force         



#windows_mait.ps1
param($Server)
        $User = 'XXXX'
        $File = "\\gearhead\scripts$\Password.txt"
        $Password = (Get-Content "\\gearhead\scripts$\Password.txt" | ConvertTo-SecureString)
        $Cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password
        $DNSname = $server.DNSHostName
        $PSsession = New-PSSession -ComputerName $DNSname -Credential $Cred
        if(-not($PSsession))
            {
                Write-Warning "$DNSname inaccessible, skipping!"
            }
        else
            {
                "Entering PSSession to $DNSname"
                ipmo \\gearhead\scripts$\PSWindowsUpdate
                "Running Windows Updates on $DNSname"
                Get-WUInstall -acceptall -IgnoreReboot -IgnoreUserInput 
                "Closing remote PSSession on $DNSname"
                Remove-PSSession $PSsession
                $Date = Get-Date
                "Rebooting $DNSname at $Date and waiting..."
                Restart-Computer -ComputerName $DNSname -Wait -Force
                $Date = Get-Date
                "$DNSname came back online at $Date"
            }



#vm_snapshot.ps1
param($server)
Get-VM -computername $server.DNSHostName | Where-Object {$_.State -eq "Running"} | Stop-VM
Get-VM -computername $server.DNSHostName | Where-Object {$_.State -eq "Off"} | CheckPoint-VM 
Get-VM -computername $server.DNSHostName | Where-Object {$_.State -eq "Off"} | Remove-VMSnapshot (Get-VMSnapshot | Where-Object {$_.CreationTime -lt (Get-Date).AddDays(-15)}) 
