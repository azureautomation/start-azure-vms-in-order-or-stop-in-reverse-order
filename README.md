Start Azure VMs in order or stop in reverse order.
==================================================

            

Start Azure VMs in order or stop them in reverse order.  The script requires two parameters:  action and JSONConfigFile.  The action is start, stop, or test.  The JSONConfigFile is the URL link to the JSON configuration file (the file
 can be saved on Azure on a storage account blob container).  The script has a sample JSON Config file showing two sample VMs to start/stop which you can edit to however many VMs you want.  The script is designed to be automated in an Azure Automation
 Account.  Because you specifiy the action and config file, you can use this same script to start or stop different groups of VMs.  You can include a 'Run As account' in it to connect to a SendGrid resource for the purpose of sending you emails (script
 success, script failure, or either success or failure).  Should the script detect a failure in starting/stopping VMs, it will stop the process of starting/stopping VMs where the failure occured.  The JSON Config file is pretty simple.  It has
 global values for email recipeints, email on none/success/failure/all, and a group of VMS to start or stop.  Each VM has settings for the name, resource group, start order (will be stop in reverse order), start delay in seconds, start timeout to error,
 stop delay, and stop timeout to error.  As far as email goes, the script includes simple instructions to configure sending email from Azure through a SendGrid email account.  The credentials are NOT stored in the script.  Instead, the script
 reads the credentials from the Automation Account (credentials are stored securely in that).


 


 

 

        
    
TechNet gallery is retiring! This script was migrated from TechNet script center to GitHub by Microsoft Azure Automation product group. All the Script Center fields like Rating, RatingCount and DownloadCount have been carried over to Github as-is for the migrated scripts only. Note : The Script Center fields will not be applicable for the new repositories created in Github & hence those fields will not show up for new Github repositories.
