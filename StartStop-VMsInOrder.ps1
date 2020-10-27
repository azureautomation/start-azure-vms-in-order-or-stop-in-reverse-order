# Begin PowerShell Runbook - for Windows Azure
#############################
# Runbook Name and parameters: StartStop-VMsInOrder -action <action> -JSONConfigFile <Filename.json>
# Runbook type:  PowerShell (do not select type PowerShell WorkFlow)
# 
# Process:
#     Perform <action> on the group of VMs configured in JSONConfigFile <Filename.json>
#     Report to Function send-email:  Function configured to use SendGrid
#
# Where: <action> = { Start | Stop | Test }
# Where: <Filename.json> = URL to JSON config file (i.e. https://storacct.blob.core.windows.net/blobcontainer/Filename.json)
#
# When: <action> = "Start" then start in order
# When: <action> = "Stop" then stop in reverse order
# When: <action> = "Test" then do not Start or Stop VMs, output to console {JSON data, VM exists, Email to be sent},   
#                   Send email if ((action "Test" is Success) and (JSON.EmailOn is All)).
# 
# The JSON-Config-file can be saved in Azure on a storage account > Blob > Container.  Record the URL for it.  You can
# test the URL in a web browser.  The file can be created/edited with a text editor.  
#
# Begin JSON-Config file example "Filename.json" (exclude # at beginning of lines, MetaData values not required)
#
#{
#	"JSONMetaData": "JSON config file for Runbook StartStop-VMsInOrder",
#	"JSONVMGroupName" : "Test1 Servers",
#	"EmailRecipeintsMetaData": "multiple recipients are comma seperated inside quotes (no space after comma)",
#	"EmailRecipients": "john.doe@contoso.com,Helpdesk@contoso.com",
#	"EmailOnMetadata": "EmailOn = {None | Success | Failure | All}",
#	"EmailOn": "None",
#	"VMsMetaData": "[ {Name,ResourceGroup,Order,StartDelaySec,StartTimeoutSec,StopDelaySec,StopTimeoutSec}, {...}, {...}, {...} ]",
#	"VMs": [
#		{
#			"Name": "Server1",
#			"ResourceGroup": "Test1",
#			"Order": "1",
#			"StartDelaySec": "0",
#			"StartTimeoutSec": "480",
#			"StopDelaySec": "30",
#			"StopTimeoutSec": "300"
#		},
#		{
#			"Name": "Server2",
#			"ResourceGroup": "Test2",
#			"Order": "2",
#			"StartDelaySec": "60",
#			"StartTimeoutSec": "600",
#			"StopDelaySec": "0",
#			"StopTimeoutSec": "240"
#		}
#	]
#}
#
# End JSON-Config-file example
#
# Runbook Prerequisites:
# 1. Runbook Authentication for VMs:  Azure "Automation Account" resource containing a "Run As account" (new or existing resource)
# 2. Runbook Email:  Azure "SendGrid account" resource (new or existing resource)
#    a. Select "+ Create a resource".  Add resource name="SendGrid Email Delivery"; Publisher="SendGrid"; Cagegory="Web"
#    b. Complete the signup form:  i.e. Name = "CompanySendGridAccount1"; Password = Password (record it, this is your SendGrid password);
#         Pricing Tier = Free (max 100 emails/day); Resource Group; Contact information = email address to confirm SendGrid account
#    c. Open the SendGrid resource.  Click Manage to initiate email verification.  Verify with the email received.
#    d. Open the SendGrid resource.  Click Manage.   In the webpage, under settings, Click API Keys.  Create API key - grant minimum of 
#       full access to Mail Send.  Save API key if desired (not used in this script authentication and can be deleted/recreated later).
#    e. Open the SendGrid resource.  In the middle pane, click the key icon "Keys".  Record the USERNAME
#       (begins with azure, ends with azure.com) this script uses to authenticate to SendGrid (this is your SendGrid username).  Record
#       the SMTP SERVER name.  Edit the script value $SMTPServer to match.
# 3. Runbook Authentication for Email:  Azure Automation Account stores Shared Resource "Credentials"
#    Select the automation account used for this runbook.  In the middle pane, select Shared Resources\Credentials.
#    Select "+ Add a credential":
#    a. Create a name for the credential (i.e. "CONTOSO-AutomationAccount1Cred1").
#       Edit script variable $AutomationAccountStoredCredential to match.
#    b. Username = USERNAME used to authenticate to SendGrid (step 2e above).
#    c. Password = Password used to authenticate to SendGrid (step 2b above).
#
# Notes:
# SendGrid Portal for monitoring activity:  https://sendgrid.com
# Login:  Username and Password from step 3 above
# You can also open the Sendgrid resource in Azure and click Manage. 
#
# Reference of VM status codes seen by PowerShell for VM states
# VM is      $Status.Code             $Status.DisplayStatus
# Stopped    PowerState/deallocated   VM deallocated
# Starting   PowerState/starting      VM starting
# Running    PowerState/running       VM running
# Stopping   PowerState/deallocating  VM deallocating
#
# Written:  James Anderson 2018
# Version:  2 - SendGrid added
#############################
# Script Input Parameters (do not edit).  These are the paramters you must provide in Azure to run it.
Param (
    [Parameter(Mandatory=$true)][ValidateSet("Start","Stop","Test")][String]$Action,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][String]$JSONConfigFile
)
#############################
# Editable Variables
# Email Subject = {$Subject1 | $Subject2} + $Subject3
#     + $Actioning + " VM Group " + $JSONVMGroupName + " in { order | reverse order }."
$Subject1 = "Success:  "
$Subject2 = "ERROR:  "
$Subject3 = "Workbook StartStop-VMsInOrder "
$EmailFrom = "StartStop.VMsInOrder@azure.com"    # used by Function Send-Email
$SMTPServer = "smtp.sendgrid.net"    # used by Function Send-Email, value defined in sendgrid account resource
$AutomationAccountStoredCredential = "CONTOSO-AutomationAccount1Cred1"  # Name of Automation Account Stored Credential
$CheckActionSec = 5  # seconds to wait between checking Action success until timeout
#############################
# Script Functions (do not edit)
Function Send-Email {
    # Send email using SendGrid Account.
    # Function Scope variables inherit default values defined in the parent (script) scope:
    # $CR, $LF, $CRLF, $AutomationAccountStoredCredential, $EmailFrom, $SMTPServer,
    # $EmailRecipients (comma seperated in string), $Subject, $Body
    $SendGridCredential = Get-AutomationPSCredential -Name $AutomationAccountStoredCredential
    $EmailTo = $EmailRecipients.split(",")
    $bodyhtml = @(($Body -replace $CR,"").split($LF)) -join "<br/>"
    Send-MailMessage -from $EmailFrom -to $EmailTo -smtpServer $SMTPServer -Credential $SendGridCredential -Usessl `
        -Port 587 -subject $Subject -Body $Bodyhtml -BodyAsHtml
}
#############################
# Main Section (do not edit).  Label "Main" on Do loop, Read JSON, initialize script variables
:Main Do {
    $CR = "$([char]13)"
    $LF = "$([char]10)"
    $CRLF = $CR + $LF
    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    # Read from file method:  $JSON = Get-Content -path $JSONConfigFile | ConvertFrom-Json
    $JSON = Invoke-WebRequest -Uri $JSONConfigFile -UseBasicParsing | ConvertFrom-Json
    If ($Action -eq "Stop") {
        $Actioning = $Action + "ping"
    }
    Else {
        $Actioning = $Action + "ing"
    }
    $Subject3 = $Subject3 + $Actioning + " VM Group " + $JSON.JSONVMGroupName
    $Body = ((Get-Date) -as [string]) + ":  " + $Actioning + " VM Group " + $JSON.JSONVMGroupName + " in "
    If ($Action -eq "Stop") {
        $Body = $Body + "reverse "
    }
    $Body = $Body + "order." + $CRLF
    If ($Action -eq "Test") {
        $CRLF + "JSON:" + $CRLF + $JSON + $CRLF + $CRLF
    }
    $EmailRecipients = $JSON.EmailRecipients
    # Connect Automation Account RunAs.  If error { break main }
    $connectionName = "AzureRunAsConnection"
    Try {
        $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName         
        Add-AzureRmAccount `
            -ServicePrincipal `
            -TenantId $servicePrincipalConnection.TenantId `
            -ApplicationId $servicePrincipalConnection.ApplicationId `
            -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint
    }
    catch {
        $Subject = $Subject2 + $Subject3
        if (!$servicePrincipalConnection) {
            $Body = $Body + ((Get-Date) -as [String]) + ":  ERROR - AzureRunAsConnection not found." + $CRLF
        }
        else {
            $Body = $Body + ((Get-Date) -as [String]) + ":  ERROR - Connecting to Azure.  Exception:  " `
                + $_.Exception + $CRLF
        }
        $Body = $Body + ((Get-Date) -as [String]) + ":  Aborting Runbook." + $CRLF
        If ($Action -eq "Test") {
            "Email Recipients:" + $CRLF + $JSON.EmailRecipients + $CRLF
            "Subject:" + $CRLF + $Subject + $CRLF + $CRLF
            "Body:" + $CRLF + $Body + $CRLF + $CRLF
        }
        ElseIf (($JSON.EmailOn -eq "Failure") -or ($JSON.EmailOn -eq "All")) {
            Send-Email
        }
        Break Main
    }
    # For Each VM { check present }, if not success { break main }
    $Success = $true
    $JSON.VMs | ForEach-Object {
        $VM = $_
        $VMPresent = $true
        $Name = Get-AzureRmVm -ResourceGroupName ($VM.ResourceGroup) -Name ($VM.Name) `
            -ErrorAction SilentlyContinue
        If ($Name -eq $null) {
            $Success = $false
            $VMPresent = $false
            $Body = $Body + ((Get-Date) -as [String]) + ":  ERROR - VM " + $VM.Name `
                + " not present." + $CRLF
        }
        If ($Action -eq "Test") {
            If ($VMPresent -eq $true) {
                "VM " + $VM.Name + " in Resource Group " + $VM.ResourceGroup + " is present."
            }
            Else {
                "ERROR - VM " + $VM.Name + " in Resource Group " + $VM.ResourceGroup + " not present."
            }
            $DisplayStatus = "unknown"
            $VMStatuses = $(Get-AzureRmVM -Name ($VM.Name) -ResourceGroupName ($VM.ResourceGroup) -Status).Statuses
            ForEach ($status in $VMStatuses) {
                If ($Status.Code -like "PowerState*") {
                    $State = $Status.Code.Split('/')[1]
                    $DisplayStatus = $Status.DisplayStatus
                }
            }
            "VM " + $VM.Name + " current state is " + $DisplayStatus
        }
    }
    If ($Success -eq $false) {
        $Subject = $Subject2 + $Subject3
        $Body = $Body + ((Get-Date) -as [String]) + ":  Aborting Runbook." + $CRLF
        If ($Action -eq "Test") {
            $CRLF + "Email Recipients:" + $CRLF + $JSON.EmailRecipients + $CRLF + $CRLF
            "Subject:" + $CRLF + $Subject + $CRLF + $CRLF
            "Body:" + $CRLF + $Body + $CRLF + $CRLF
        }
        ElseIf (($JSON.EmailOn -eq "Failure") -or ($JSON.EmailOn -eq "All")) {
            Send-Email
        }
        Break Main
    }
    If ($Action -eq "Start") {
        # for each VM in order { wait StartDelay, Start VM, ... 
        $JSON.VMs | Sort-Object -Property Order | ForEach-Object -Process {
            $VM = $_
            $Body = $Body + ((Get-Date) -as [string]) + ":  Waiting " + $VM.StartDelaySec `
                + " seconds to " + $Action + " " + $VM.Name + "." + $CRLF
            Start-Sleep -seconds $VM.StartDelaySec
            $Body = $Body + ((Get-Date) -as [string]) + ":  " + $Actioning + " " `
                + $VM.Name + ".  " + $VM.StartTimeoutSec + " seconds to timeout." + $CRLF
            $EndState = "running"
            $TimeoutSec = $VM.StartTimeoutSec
            $Timeout = $false
            $State = "Unknown"
            $Success = $false
            $StopWatch.Reset()
            $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            $Return = Start-AzureRmVM -Name ($VM.Name) -ResourceGroupName ($VM.ResourceGroup)
            $Body = $Body + ((Get-Date) -as [string]) + ":  " + $Actioning + " VM " + $VM.Name + ", Azure reports " `
                + $Action + " is " + $Return.IsSuccessStatusCode + $CRLF
            # ... Do { Check Status } until (success or timeout). If not Success { Break Main } }
            Do {
                Start-Sleep -seconds $CheckActionSec
                $VMStatuses = $(Get-AzureRmVM -Name ($VM.Name) -ResourceGroupName ($VM.ResourceGroup) -Status).Statuses
                ForEach ($status in $VMStatuses) {
                    If ($Status.Code -like "PowerState*") {
                        $State = $Status.Code.Split('/')[1]
                        $DisplayStatus = $Status.DisplayStatus
                    }
                }
                If ($State -like $EndState) {
                    $Success = $true
                }
                If (($StopWatch.Elapsed.TotalSeconds -as [int]) -gt ($TimeoutSec -as [int])) {
                    $Timeout = $True
                }
            } Until (($Success -eq $true) -or ($Timeout -eq $true))
            If ($Success -eq $false) {
                $Subject = $Subject2 + $Subject3
                $Body = $Body + ((Get-Date) -as [string]) + ":  ERROR - " + $Actioning + " " + $VM.Name `
                    + " timed out. " + $DisplayStatus + " in " `
                    + (($StopWatch.Elapsed.TotalSeconds -as [int]) -as [String]) + " seconds." + $CRLF
                $Body = $Body + ((Get-Date) -as [String]) + ":  Aborting Runbook." + $CRLF
                If (($JSON.EmailOn -eq "Failure") -or ($JSON.EmailOn -eq "All")) {
                    Send-Email
                }
                Break Main
            }
            Else {
                $Body = $Body + ((Get-Date) -as [string]) + ":  " + $Actioning + " " + $VM.Name `
                    + " State changed to " + $DisplayStatus + " in " `
                    + (($StopWatch.Elapsed.TotalSeconds -as [int]) -as [String]) `
                    + " seconds." + $CRLF
            }
        }
    }
    If ($Action -eq "Stop") {
        # for each VM in reverse order { wait StopDelay, Stop VM, ... 
        $JSON.VMs | Sort-Object -descending -Property Order | ForEach-Object -Process {
            $VM = $_
            $Body = $Body + ((Get-Date) -as [string]) + ":  Waiting " + $VM.StopDelaySec + " seconds to " `
                + $Action + " " + $VM.Name + "." + $CRLF
            Start-Sleep -seconds $VM.StopDelaySec
            $Body = $Body + ((Get-Date) -as [string]) + ":  " + $Actioning + " " + $VM.Name + ".  " + $VM.StopTimeoutSec `
                + " seconds to timeout." + $CRLF
            $EndState = "deallocated"
            $TimeoutSec = $VM.StopTimeoutSec
            $Timeout = $false
            $State = "Unknown"
            $Success = $false
            $StopWatch.Reset()
            $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()
            $Return = Stop-AzureRmVM -ResourceGroupName ($VM.ResourceGroup) -Name ($VM.Name) -Force
            $Body = $Body + ((Get-Date) -as [string]) + ":  " + $Actioning + " VM " + $VM.Name + ", Azure reports " `
                + $Action + " is " + $Return.IsSuccessStatusCode + $CRLF
            # ... Do { Check Status } until (success or timeout). If not Success { Break Main } }
            Do {
                Start-Sleep -seconds $CheckActionSec
                $VMStatuses = $(Get-AzureRmVM -Name ($VM.Name) -ResourceGroupName ($VM.ResourceGroup) -Status).Statuses
                ForEach ($status in $VMStatuses) {
                    If ($Status.Code -like "PowerState*") {
                        $State = $Status.Code.Split('/')[1]
                        $DisplayStatus = $Status.DisplayStatus
                    }
                }
                If ($State -like $EndState) {
                    $Success = $true
                }
                If (($StopWatch.Elapsed.TotalSeconds -as [int]) -gt ($TimeoutSec -as [int])) {
                    $Timeout = $True
                }
            } Until (($Success -eq $true) -or ($Timeout -eq $true))
            If ($Success -eq $false) {
                $Subject = $Subject2 + $Subject3
                $Body = $Body + ((Get-Date) -as [string]) + ":  ERROR - " + $Actioning + " " + $VM.Name `
                    + " timed out. " + $DisplayStatus + " in " `
                    + (($StopWatch.Elapsed.TotalSeconds -as [int]) -as [String]) + " seconds." + $CRLF
                $Body = $Body + ((Get-Date) -as [String]) + ":  Aborting Runbook." + $CRLF
                If (($JSON.EmailOn -eq "Failure") -or ($JSON.EmailOn -eq "All")) {
                    Send-Email
                }
                Break Main
            }
            Else {
                $Body = $Body + ((Get-Date) -as [string]) + ":  " + $Actioning + " " + $VM.Name `
                    + " State changed to " + $DisplayStatus + " in " `
                    + (($StopWatch.Elapsed.TotalSeconds -as [int]) -as [String]) `
                    + " seconds." + $CRLF
            }
        }
    }
    # Start, Stop, or Test action completed successfully (no Break Main), Send-Email
    $Subject = $Subject1 + $Subject3
    $Body = $Body + ((Get-Date) -as [String]) + ":  Success.  Runbook Ending." + $CRLF
    If ($Action -eq "Test") {
        If ($JSON.EmailOn -eq "All") {
            $CRLF + "JSON SendOn is " + $JSON.EmailOn + ".  Sending email." + $CRLF + $CRLF
            Send-Email
        }
        $CRLF + "Email Recipients:" + $CRLF + $JSON.EmailRecipients + $CRLF + $CRLF
        "Subject:" + $CRLF + $Subject + $CRLF + $CRLF
        "Body:" + $CRLF + $Body + $CRLF + $CRLF
    }
    Else {
        If (($JSON.EmailOn -eq "Success") -or ($JSON.EmailOn -eq "All")) {
            Send-Email
        }
    }
# execute Do loop only once using Until ($true)
} Until ($true)
# Break Main will exit Do loop labeled Main to here
$StopWatch.Reset()
#############################
# End PowerShell Runbook
