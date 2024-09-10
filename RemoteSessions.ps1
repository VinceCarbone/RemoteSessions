param (    
    [Parameter(Mandatory=$true)][string]$samaccount,
    [switch]$logoff
)

# Checks to make sure the samaccount is valid
If(-not(Get-ADUser $samaccount -erroraction SilentlyContinue)){
    Write-Host "Cannot find $samaccount in the domain" -ForegroundColor Red
    Exit
}

#Gets all servers in Domain
$servers = Get-ADComputer -filter {enabled -eq $true} -properties serviceprincipalname, operatingsystem | Where-Object operatingsystem -like "*server*"

#Removes clusters and un-pingable servers from list
$i = 0
$realservers = @(
    ForEach($server in $servers){
        $is_server = $false
        $spns = $server | Select-Object -ExpandProperty serviceprincipalname
        ForEach($spn in $spns){
            If($spn -like "*TERMSRV*"){$is_server = $true}
        }
        If($is_server -eq $true){
            If(Test-Connection -ComputerName $server.name -Count 1 -BufferSize 16 -ErrorAction SilentlyContinue){Write-Output $server}
        }
        Write-Progress -Activity "Pinging $($server.name)" -PercentComplete (($i / $servers.count)*100)    
        $i++
    }
)
Write-Progress -Activity "Pinging" -Status Ready -Completed

# Runs PowerShell against all servers to find all remote sessions
Write-Host "Querying sessions on all pingable servers"
$RemoteSessions = @(Invoke-Command -ComputerName $($realservers.name) -ScriptBlock {qwinsta | foreach {(($_.trim() -replace “  +”,”,”))} | ConvertFrom-Csv} -ErrorAction SilentlyContinue)

# Narrows down list of results to just sessions for the user listed above
$SessionsToKill = @($RemoteSessions | Where-Object username -eq $samaccount)
$SessionsToKill += @($RemoteSessions | Where-Object sessionname -eq $samaccount)

# Displays list of remote sessions
If($SessionsToKill){
    $SessionsToKill | Format-Table sessionname, username, id, state, pscomputername -AutoSize

    # Terminates the sessions and unlocks the user account
    If($logoff){
        ForEach($RemoteSession in $SessionsToKill){
            If($RemoteSession.pscomputername -ne $env:COMPUTERNAME){
                Write-Host "Logging off $($RemoteSession.pscomputername)"        
                If($RemoteSession.sessionname -eq $samaccount){rwinsta /server:$($RemoteSession.pscomputername) $RemoteSession.username}
                If($RemoteSession.username -eq $samaccount){rwinsta /server:$($RemoteSession.pscomputername) $RemoteSession.ID}
            }
        }

        # Unlocks the user account
        Unlock-ADAccount -Identity $samaccount
    }
}Else{Write-Host "Unable to find any remote sessions for $samaccount"}