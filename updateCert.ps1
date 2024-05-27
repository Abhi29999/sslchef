$Server = "localhost"
$listener = Get-DbaAgListener -sqlInstance localhost
$agl = $listener.Name
Write-Host "agl : $agl"

$certpass = Get-Content -Path "C:\Windows\System32\certpass.json" | ConvertFrom-Json

$environmentVariable = Invoke-Command -ComputerName $Server -ScriptBlock {
    [System.Environment]::GetEnvironmentVariable("BL_SQL_ENVIRONMENT")
}

if ($environmentVariable -eq "SB") {
    Write-Host "$Server has BL_SQL_ENVIRONMENT set to 'SB'"
    # use password for 'SB' 46p5wgSLLBRZ37oyvB59  '"'+$certpass.prd+'"'
    $plainText = $certpass.sb
    Write-Host $plainText
    $mypwd = ConvertTo-SecureString $plainText -AsPlainText -Force
    Write-Host $mypwd
    $username = $certpass.sb_user
    $password = $certpass.sb_pass
    $securePass = ConvertTo-SecureString -String $password -AsPlainText -Force
    Write-Host "sb pass $plainText"
    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $securePass

}
elseif ($environmentVariable -eq "PRD") {
    Write-Host "$Server has BL_SQL_ENVIRONMENT set to 'PRD'"
    # use password for 'PRD' 6vrULhux63iwD5VUHIAt
    $plainText = $certpass.prd #"6vrULhux63iwD5VUHIAt"
    Write-Host "prd pass $plainText"
}
else {
    Write-Host "$Server has BL_SQL_ENVIRONMENT set to an unknown value: $environmentVariable"
    # Handle other cases
    exit
}


#code to run the cert process if the cert folder exists in the shared drive.
Write-Host $agl
$Path = "\\us2nas01\Transfer_Temp\certificates\$agl.cjp.blackline.corp"
Write-Host "cert path $Path"
if (Test-Path -Path $Path) {
# Path exists, run certApply code
Write-Host "The path exists. Running additional code..."
# ApplyCert code

#Get most recent certificate .pfx file name from Jenkins job output folder
$Path = "\\us2nas01\Transfer_Temp\certificates\$agl.cjp.blackline.corp"
$folder = Get-childitem -Path $Path | sort-object -property CreationTime -Descending | select-object -First 1 | Select-Object -ExpandProperty Name
$sourcefolder = "$path\$folder"

$pfxfile = Get-childitem -Path $sourcefolder | where-object { $_.Name -Like "*.pfx" -and $_.Name -NotLike "*temp*" } | select-object -ExpandProperty Name
$sourcefile = "$sourcefolder\$pfxfile"
Write-Host "$sourcefile"

#Get certificate thumbprint
$thumbprint = (Get-PfxData  -FilePath $sourcefile -Password $mypwd).EndEntityCertificates.Thumbprint
#Get list of all nodes in AG replica
$AGReplica = @()
$AGReplica = Get-DbaAgReplica -SqlInstance $agl | select-object -expandproperty Name

foreach ($node in $AGReplica) {
    #Check if thumbprint already exists on AG node
    $TP = Invoke-command -ComputerName $node -ArgumentList $thumbprint -scriptblock { param($thumbprint) (Get-ChildItem -Path Cert:\LocalMachine\My | where-object Thumbprint -EQ $thumbprint).Thumbprint }
    If ($TP -eq $thumbprint) {

        Write-Host "All good with $node"
    }
    Else {

        $destination = "\\" + $node + "\c$\admin\certs"
        Invoke-Command -ComputerName $node -ScriptBlock {

            If (!(test-path "c:\admin\certs")) {

                Write-Host "Path Doesnot Exist, so creating folder"
                New-Item -ItemType Directory -Force -Path "c:\admin\certs"

            }
            else {

                Remove-Item "c:\admin\certs\*" -Recurse -Force
            }
        }
        #Copy .pfx file to AG node
        Copy-Item –Path $sourcefile –Destination $destination

        Invoke-Command -ComputerName $node -ArgumentList $destination, $mypwd, $thumbprint, $node, $UserCred -ScriptBlock {
            param($destination , $mypwd, $thumbprint, $node, $UserCred)

            $certname = (Get-ChildItem -Path $destination | Select-Object -Property Name).Name

            Import-Module -Name PKI, dbatools
            #Import pfx certificate
            Import-PfxCertificate -FilePath $destination"\"$certname -CertStoreLocation Cert:\LocalMachine\My -Password $mypwd

            ##Remove-DbaNetworkCertificate -SqlInstance $srv
            ##Get-DbaService -Type engine,agent|Stop-DbaService -Type engine,Agent -Force|Start-DbaService -Type engine,Agent

            $Instance = @()
            #Find list of all SQL instances(named or default) on AG node
            $Instance = Find-DbaInstance -ComputerName $node | Select-Object -Property @{Name = "SQLInstance"; Expression = { if ($_.InstanceName -eq "MSSQLSERVER" -or $_.InstanceName -eq "") { $_.ComputerName } else { $_.ComputerName + "\" + $_.InstanceName } } } | select-object -ExpandProperty SQLInstance
            #Apply cert to SQL Instance on AG node
            $Instance | foreach-object -Process { Set-DbaNetworkCertificate -SqlInstance $_ -Thumbprint $thumbprint -credential $UserCred }

        }
    }
}
} else {
# Path does not exist
Write-Host "The path does not exist."
}
