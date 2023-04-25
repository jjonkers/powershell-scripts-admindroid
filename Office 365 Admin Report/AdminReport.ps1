﻿<#
=============================================================================================
Name:           Export Microsoft 365 Admin Report using MS Graph PowerShell
Description:    This script exports Microsoft 365 admin role group membership to CSV
Version:        3.0
website:        o365reports.com
Script by:      O365Reports Team
For detailed Script execution: https://o365reports.com/2021/03/02/Export-Office-365-admin-role-report-powershell
============================================================================================
#>
param ( 
[switch] $RoleBasedAdminReport, 
[switch] $ExcludeGroups,
[String] $AdminName = $null, 
[String] $RoleName = $null,
[string] $TenantId,
[string] $ClientId,
[string] $CertificateThumbprint
)
   
#Check for module availability
$MsGraphModule =  Get-Module Microsoft.Graph -ListAvailable
if($MsGraphModule -eq $null)
{ 
    Write-host "Important: Microsoft graph module is unavailable. It is mandatory to have this module installed in the system to run the script successfully." 
    $confirm = Read-Host Are you sure you want to install Microsoft graph module? [Y] Yes [N] No  
    if($confirm -match "[yY]") 
    { 
        Write-host "Installing Microsoft graph module..."
        Install-Module Microsoft.Graph -Scope CurrentUser
        Write-host "Microsoft graph module is installed in the machine successfully" -ForegroundColor Magenta 
    } 
    else
    { 
        Write-host "Exiting. `nNote: Microsoft graph module must be available in your system to run the script" -ForegroundColor Red
        Exit 
    } 
}
if(($TenantId -ne "") -and ($ClientId -ne "") -and ($CertificateThumbprint -ne ""))  
{  
    Connect-MgGraph  -TenantId $TenantId -AppId $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction SilentlyContinue -ErrorVariable ConnectionError|Out-Null
    if($ConnectionError -ne $null)
    {    
        Write-Host $ConnectionError -Foregroundcolor Red
        Exit
    }
}
else
{
    Connect-MgGraph -Scopes "Directory.Read.All"  -ErrorAction SilentlyContinue -Errorvariable ConnectionError |Out-Null
    if($ConnectionError -ne $null)
    {
        Write-Host "$ConnectionError" -Foregroundcolor Red
        Exit
    }
}
Write-Host "Microsoft Graph Powershell module is connected successfully" -ForegroundColor Green
Select-MgProfile beta
Write-Host "Preparing admin report..." 
$Admins=@() 
$RoleList = @() 
$OutputCsv=".\AdminReport_$((Get-Date -format MMM-dd` hh-mm` tt).ToString()).csv" 
function Process_AdminReport
{ 
    $AdminMemberOf=Get-MgUserMemberOf -UserId $Admins.Id |Select-Object -ExpandProperty AdditionalProperties
    $AssignedRoles=$AdminMemberOf|?{$_.'@odata.type' -eq '#microsoft.graph.directoryRole'} 
    $DisplayName=$Admins.DisplayName
    if($Admins.AssignedLicenses -ne $null)
    { 
        $LicenseStatus = "Licensed" 
    }
    else
    { 
        $LicenseStatus= "Unlicensed" 
    } 
    if($Admins.AccountEnabled -eq $true)
    { 
        $SignInStatus = "Allowed" 
    }
    else
    { 
        $SignInStatus = "Blocked" 
    } 
    Write-Progress -Activity "Currently processing: $DisplayName" -Status "Updating CSV file"
    if($AssignedRoles -ne $null) 
    { 
        $ExportResult=@{'Admin EmailAddress'=$Admins.mail;'Admin Name'=$DisplayName;'Assigned Roles'=(@($AssignedRoles.displayName)-join ',');'License Status'=$LicenseStatus;'SignIn Status'=$SignInStatus } 
        $ExportResults= New-Object PSObject -Property $ExportResult         
        $ExportResults | Select-Object 'Admin Name','Admin EmailAddress','Assigned Roles','License Status','SignIn Status' | Export-csv -path $OutputCsv -NoType -Append  
    } 
} 
function Process_RoleBasedAdminReport
{ 
    $AdminList = Get-MgDirectoryRoleMember -DirectoryRoleId $AdminRoles.Id |Select-Object -ExpandProperty AdditionalProperties
    $RoleName=$AdminRoles.DisplayName
    if($ExcludeGroups.IsPresent)
    {
        $AdminList=$AdminList| ?{$_.'@odata.type' -eq '#microsoft.graph.user'}
        $DisplayName=$AdminList.displayName 
    }
    else
    {
        $DisplayName=$AdminList.displayName
    }
    if($DisplayName -ne $null)
    { 
        Write-Progress -Activity "Currently Processing $RoleName role" -Status "Updating CSV file"
        $ExportResult=@{'Role Name'=$RoleName;'Admin EmailAddress'=(@($AdminList.mail)-join ',');'Admin Name'=(@($DisplayName)-join ',');'Admin Count'=$DisplayName.Count} 
        $ExportResults= New-Object PSObject -Property $ExportResult 
        $ExportResults | Select-Object 'Role Name','Admin Name','Admin EmailAddress','Admin Count' | Export-csv -path $OutputCsv -NoType -Append
    }
}
 
#Check to generate role based admin report
if($RoleBasedAdminReport.IsPresent)
{ 
    Get-MgDirectoryRole -All| ForEach-Object { 
    $AdminRoles= $_ 
    Process_RoleBasedAdminReport 
    } 
}

#Check to get admin roles for specific user
elseif($AdminName -ne "")
{ 
    $AllUPNs = $AdminName.Split(",")
    ForEach($Admin in $AllUPNs) 
    { 
        $Admins=Get-MgUser -UserId $Admin -ErrorAction SilentlyContinue 
        if($Admins -eq $null)
        { 
            Write-host "$Admin is not available. Please check the input" -ForegroundColor Red 
        }
        else
        { 
            Process_AdminReport 
        } 
    }
}

#Check to get all admins for a specific role
elseif($RoleName -ne "")
{ 
    $RoleNames = $RoleName.Split(",")
    ForEach($Name in $RoleNames) 
    { 
        $AdminRoles= Get-MgDirectoryRole -Filter "DisplayName eq '$Name'" -ErrorAction SilentlyContinue 
        if($AdminRoles -eq $null)
        { 
            Write-Host "$Name role is not available. Please check the input" -ForegroundColor Red 
        }
        else
        { 
            Process_RoleBasedAdminReport 
        } 
    } 
}

#Generating all admins report
else
{ 
    Get-MgUser -All | ForEach-Object { 
    $Admins= $_ 
    Process_AdminReport 
    } 
} 

#Open output file after execution 
if((Test-Path -Path $OutputCsv) -eq "True") 
{ 
    Write-Host "The Output file availble in $outputCsv" -ForegroundColor Green 
    $prompt = New-Object -ComObject wscript.shell    
    $UserInput = $prompt.popup("Do you want to open output file?",` 0,"Open Output File",4)    
    If ($UserInput -eq 6)    
    {    
        Invoke-Item "$OutputCsv"  
        Write-Host "Report generated  successfuly"  -ForegroundColor Green 
    }
} 
else
{
    Write-Host "No data found" -ForegroundColor Red
}
Disconnect-MgGraph|Out-Null
