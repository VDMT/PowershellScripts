 
### Script: determine CNAME entries that are not active
### Queries all CNAME and A records in a DNS Zone, determines CNAME's that are
### not associated to a host with a IP address

### find zone names' using command:
# Get-DnsServerZone -ComputerName $dnsServer

### enter zone name and DNS server below..
$zone = ''
$dnsServer = ''

$zoneCollection=@()
$exportResultFile = "c:\temp\InactiveCNAMEList for $zone.csv"



function NewHostDNSEntry {
    param (
        [String]$hostname, [String]$recordType, [String]$zoneName, [String]$iPv4, [String]$hostAlias, [String]$pingResult
    )
    New-Object -TypeName psobject `
        -Property @{Hostname=$hostname; RecordType=$recordType; ZoneName=$zoneName; IPv4=$iPv4; `
        HostAlias=$hostAlias; PingResult=$pingResult;}
}

Get-DnsServerResourceRecord -Zonename $zone -ComputerName $dnsServer | 
    Where-Object {$_.RecordType -eq 'CNAME' -or $_.recordType -eq 'A'} | 
    Select-Object `
        hostname, 
        recordType, 
        @{n='ZoneName';Expression={$zone}},
        @{n='IPv4';e={$_.RecordData.IPv4Address}},
        @{n='HostAlias';e={$_.RecordData.HostnameAlias}},
        @{n='Timestamp';e={$_.Timestamp}} `
    | ForEach-Object {
        $zoneCollection += NewHostDNSEntry -hostname $_.hostname -recordType $_.recordType -ZoneName $_.ZoneName -IPv4 $_.IPv4 -HostAlias $_.HostAlias -PingResult ""
    }

## get IP's
$IPList = $zoneCollection | Where-Object { $_.IPv4 -cne '' }

## Populate IP's for all CNAME entries
foreach ($item in $zoneCollection)
{
    if ($item.RecordType -eq 'CNAME' -and $item.IPv4.Length -eq 0)
    { 
        $ip = $IPList | Where-Object { $_.hostname -eq ($item.HostAlias.Replace(".$zone.","")) } | Select-Object IPv4
        if ($ip.IPv4.Length -gt 0)
        {
            $item.IPv4 = $ip.IPv4
        }
    }
}

# Blank IP's on CNAME entry suggests no host or located in different zone
# can do a PING test, if pingable, then on different zone
# do PING on all CNAME's entries
foreach ($item in $zoneCollection | Where-Object { $_.recordtype -EQ 'CNAME' })
{
    try 
    {
        $ping = Test-Connection -ComputerName $item.HostAlias -Quiet -Count 1
        $item.PingResult = "$ping"
    }
    catch 
    {
        $item.PingResult = "False"
    }
}

## counts and stats:
Write-Host -ForegroundColor Yellow "CNAME records: " ($zoneCollection | Where-Object { $_.RecordType -eq 'CNAME' }).count 
Write-Host -ForegroundColor Yellow "A records: " ($zoneCollection | Where-Object { $_.RecordType -eq 'A' }).count
Write-Host
Write-Host -ForegroundColor Yellow "List of CNAME's that don't PING ("($zoneCollection | Where-Object {  $_.PingResult -eq 'False' }).count"):"

## result of CNAME entries that don't PING
$zoneCollection | Where-Object {  $_.PingResult -eq 'False' } | select ZoneName, Hostname, IPv4, HostAlias | Format-Table

## result to CSV
if ($exportResultFile)
{
    $zoneCollection | Export-Csv $exportResultFile
    Write-Host -ForegroundColor Yellow "Results exported to $exportResultFile"
}


