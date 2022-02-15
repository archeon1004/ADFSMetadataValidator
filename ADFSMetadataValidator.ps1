#                              Author: Lukas I (archeon1004)                               
#                      File Name: ADFSMetadataValidator.ps1                      
#                   Creation Date: February 13, 2022 11:00 PM                    
#                    Last Updated: February 13, 2022 11:04 PM                    
#                          Source Language: powershell                           
#      Repository: https://github.com/archeon1004/ADFSMetadataValidator.git      
#                                                                                
#                            --- Code Description ---                            
#               Script that checks correctness of SAML application metadata                                      

<#
.SYNOPSIS
    ADFSMetadataValidator - checks if SP SAML metadata has correct format
.DESCRIPTION
    ADFSMetadataValidator implements gui to help user check if provided SP metadata XML file is complying with XML, SAML Metadata format 
.EXAMPLE
    PS C:\> & .\ADFSMetadataValidator.ps1
    ---STARTS GUI---
.INPUTS
    Path to XML - choosed by selector
.OUTPUTS
    Returns infomration in message box
.NOTES
#>

$EABackup = $ErrorActionPreference
$ErrorActionPreference = [System.Management.Automation.ActionPreference]::Stop
Add-Type -AssemblyName System.Windows.Forms
$script:versionDetails = "1.0"
[System.Windows.Forms.Application]::EnableVisualStyles()
$script:xsdFilesPath = $null
#DEBUG vars
#$script:ValidationError = $false
#$global:adfsEnvInitialized = $true
#$global:adfsSchemaSetVar = $null
#$DebugPreference = [System.Management.Automation.ActionPreference]::Continue
Write-debug "Check if console has to be hidden"
if($DebugPreference -ne [System.Management.Automation.ActionPreference]::Continue)
{   
    Add-Type -Name Window -Namespace Console -MemberDefinition '
    [DllImport("Kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
    '
    $consolePtr = [Console.Window]::GetConsoleWindow()
    [Console.Window]::ShowWindow($consolePtr, 0)
}
else 
{
    Write-debug "Console won't be hidden"    
}
function Test-SpMetadataFile
{
    [CmdletBinding()]
    param (     
        [string]$MetadataXML,
        [switch]$OnlyReloadSchemas,
        [switch]$CheckCertificates
    )

    begin {
        class XMLValidationResults
        {
        [bool]$TestPassed
        [string[]]$Issues
        } 
        write-debug "ENTERED: Test-SpMetadataFile" 
        $Stopwatch = [System.Diagnostics.Stopwatch]::new()
        write-debug "Starting stopwatch..."
        $Stopwatch.Start()
        write-debug "Stopwatch started."
        write-debug "Checking Globals"
        write-debug "value of adfsSchemaSetVar: $($global:adfsSchemaSetVar)"
        write-debug "Tsting XML Path"
        if(((test-path $MetadataXML) -eq $false) -and (!$OnlyReloadSchemas))
        {
            write-debug "File not existing exception block"
            $Stopwatch.Stop()
            $exception = [System.ArgumentException]::new("ProvidedFileisNotExisting","MetadataXML")
            throw $exception
        }
        write-debug "Checking if only need to reload schemas"
        write-debug "value OnlyReloadSchemas: $($OnlyReloadSchemas)"
        write-debug "Preparing Validation Results Object"
        $results = New-Object -TypeName XMLValidationResults
        $results.TestPassed = $true
        $results.Issues = $null
        write-debug "Preparing Validation results finished"
        start-sleep -seconds 1
    }###end begin region
    process
    {
        if($OnlyReloadSchemas)
        {
            write-debug "entered only realod schemas part"
            Add-SPMetadataSchemas -reloadSchemas
            $Stopwatch.Stop()
            write-debug "Execution of test-spmetadatafile will end without testing reults will contain tests passed"
            write-debug "Execution taken $($Stopwatch.Elapsed.ToString())"
            write-debug "Returning resuts"
            write-debug "RESULTS testValue: $($results.TestPassed)"
            write-debug "RESULTS issuesValue: $($results.Issues)"
            Write-debug "EXITING: Test-SpMetadataFile"
            return $results
        }
        else 
        {
            write-debug "entered validation part"
            write-debug "Running Add-SPMetadataSchemas without reload param - required by the flow"
            Add-SPMetadataSchemas 
            write-debug "Creating XML document"
            $xml = New-Object System.Xml.XmlDocument
            write-debug "Created XML document. Adding Schemas..."
            try 
            {
                Write-debug "Adding schema set to XML document object"
                $xml.Schemas.Add($global:adfsSchemaSetVar) | Out-Null
            }
            catch 
            {
                write-debug "Error Caugth"
                Write-debug $_
            }            
            try 
            {
                Write-debug "read XML metadatafile into XML object"
                $xml.Load($MetadataXML)    
            }
            catch 
            {   
                write-debug "Document Loading failed. Skipping Validation"
                write-debug "Error Caugth"
                Write-debug $_
                $results.TestPassed = $false
                #$results.Issues = $_.Exception.Message
                $results.Issues = "Cannot Open the XML. Not a valid XML file."
                Write-debug "EXITING: Test-SpMetadataFile"
                return $results
            }               
            write-debug "Document Loaded. Validating XML"
            try 
            {
                $xml.Validate({
                    throw ([PsCustomObject] @{
                        MetadataXML = $MetadataXML
                        Exception = $args[1].Exception
                        })
                })
            }       
            catch 
            {
                write-debug "Validation thrown exception. XML is not compliyng with SAML standard"
                write-debug "Validation errors found!"
                #$results.Issues = $_
                $results.Issues = "Validation of the metadata failed`n$($_.Exception.Message)"
                $results.TestPassed = $false
            }
            write-debug "Checking if metadata contains required tag or is it not a valid metadata"
            if(!($xml.InnerXml -match "urn:oasis:names:tc:SAML:2.0:metadata"))  
            {
                write-debug "XML is not Valid Metadata File"
                $results.Issues = "XML is not a Service Provider metadata file"
                $results.TestPassed = $false
            }  
            else
            {
                write-debug "XML Tag check passed"
            }                
        }
        Write-debug "Validate Certificates if tests passed and it was ordered to"
        if(($results.TestPassed -eq $true) -and ($CheckCertificates))
        {
            Write-debug "Checking metadata"
            Get-MetadataCertificates -XML $xml
        }
    }#end process
    end 
    {
        write-debug "Preparing Results..."
        $Stopwatch.Stop()
        Write-debug "exeecution time label refresh"
        $LabelTime.Text= $script:EXecutionTime + " $($Stopwatch.Elapsed.ToString())"
        $LabelTime.Refresh()
        write-debug "Refresh timelable value $($LabelTime.Text)"
        write-debug "Execution taken $($Stopwatch.Elapsed.ToString())"
        write-debug "Returning resuts"
        write-debug "RESULTS testValue: $($results.TestPassed)"
        write-debug "RESULTS issuesValue: $($results.Issues)"
        Write-debug "EXITING: Test-SpMetadataFile"
        return $results
    }
}#end Test-SpMetadataFile
function Add-SPMetadataSchemas {
    param (
        [Parameter()]
        [switch]
        $reloadSchemas
    )
    write-debug "ENTERED: Add-SPMetadataSchemas"
    Write-debug "GLOBAL VAR state :$($global:adfsSchemaSetVar)"
    Write-debug "PARAM state - reloadSchemas value:$($reloadSchemas)"
    Write-debug "PATH for files needed: $($script:xsdFilesPath)"
    [scriptblock] $ValidationEventHandler = { Write-Error $args[1].ErrorDetils }
    write-debug "Starting SchemaLoading stopwatch..."
    $SchemaLoaderStopWatch = [System.Diagnostics.Stopwatch]::new()
    $SchemaLoaderStopWatch.Start()
    write-debug "Check if reloadSchemas are forced"
    if ($reloadSchemas) 
    {
        Write-debug "Removing global variable.ReloadSchemasWasUsed"
        try 
        {
            Remove-Variable adfsSchemaSetVar -scope Global
            Write-debug "Removed global variable.ReloadSchemasWasUsed"
        }
        catch 
        {
            write-debug "Catched global var state removing error"
            write-debug $_
            if(!($global:adfsSchemaSetVar))
            {
                Write-debug "Script was not initilized!"
            }
            else 
            {
                Write-debug "Different reason of exception"
            }
        } 
    }
    write-debug "Check in adfsSchemaSetVar is present or notcomplied and if not run the init"
    if (!($global:adfsSchemaSetVar) -or ($global:adfsSchemaSetVar.IsCompiled -eq $false))
    {
        write-debug "Run the init - adfsSchemaSetVar not existed"
        write-debug "Loading Schema Files..."
        write-debug "Schema processing starting..."
        $schemaReader = New-Object System.Xml.XmlTextReader "$script:xsdFilesPath\schemasaml.xsd"
        $schemaReader2 = New-Object System.Xml.XmlTextReader "$script:xsdFilesPath\assert.xsd"
        $schemaReader3 = New-Object System.Xml.XmlTextReader "$script:xsdFilesPath\sig.xsd"
        $schemaReader4 = New-Object System.Xml.XmlTextReader "$script:xsdFilesPath\xenc.xsd"
        $schemaReaderXML = New-Object System.Xml.XmlTextReader "$script:xsdFilesPath\xml.xsd"
        Write-debug "Checking global variable adfsSchemaSetVar and if it's complied"
        if (!($global:adfsSchemaSetVar) -or ($global:adfsSchemaSetVar.IsCompiled -eq $false))
        {      
            try 
            {
                $schema = [System.Xml.Schema.XmlSchema]::Read($schemaReader, $ValidationEventHandler)
                $schema2 = [System.Xml.Schema.XmlSchema]::Read($schemaReader2, $ValidationEventHandler)
                $schema3 = [System.Xml.Schema.XmlSchema]::Read($schemaReader3, $ValidationEventHandler)
                $schema4 = [System.Xml.Schema.XmlSchema]::Read($schemaReader4, $ValidationEventHandler)                
            }
            catch 
            {
                Write-debug "Schema Readers creation failed`n$($_)"
                Write-debug "Throwing SchemaFilesAreMissing Exception"
                $e = [System.IO.FileNotFoundException]::new("SchemaFilesAreMissing",$_)
                throw $e
            }   
            Write-debug "Creating SchemaSet..."
            $global:adfsSchemaSetVar = [system.xml.Schema.xmlSchemaSet]::new()
            Write-debug "Adding Schema into SchemaSet..."
            $global:adfsSchemaSetVar.Add($schema)  | Out-Null
            $global:adfsSchemaSetVar.Add($schema2)  | Out-Null
            $global:adfsSchemaSetVar.Add($schema3) | Out-Null
            $global:adfsSchemaSetVar.Add($schema4) | Out-Null
            Write-debug "Compling Schemas..."
            try 
            {
                $global:adfsSchemaSetVar.Compile() 
            }
            catch 
            {
                write-debug "Compling XML Schemas error catched"
                write-debug $_
                if ($_.Exception -match "The 'http://www.w3.org/XML/1998/namespace:lang' attribute is not declared.")
                {
                    write-debug "TEST: catch the XML not loaded exception and add additional schema"
                    write-debug "Adding missing XML schema"
                    $schemaReaderXML = New-Object System.Xml.XmlTextReader "$script:xsdFilesPath\xml.xsd"
                    try
                    {
                        $schemaxml = [System.Xml.Schema.XmlSchema]::Read($schemaReaderXML, $ValidationEventHandler)
                    }                    
                    catch 
                    {
                        Write-debug "Schema Readers creation failed`n$($_)"
                        Write-debug "Throwing SchemaFilesAreMissing Exception"
                        $e = [System.IO.FileNotFoundException]::new("SchemaFilesAreMissing",$_)
                        throw $e
                    } 
                    write-debug "Assinging XML schema to global adfsSchemaSetVar"
                    $global:adfsSchemaSetVar.Add($schemaxml)
                    write-debug "Assigment Done - compiling schemas"
                    try 
                    {
                        $global:adfsSchemaSetVar.Compile()
                    }
                    catch 
                    {
                        write-debug "Compling additional XML Schemas error catched"
                        write-debug "Value of adfsSchemaSetVar.IsCompiled: $($global:adfsSchemaSetVar.IsCompiled)"
                        write-debug "$_"
                        throw "FatalErrorOccured"
                    }  
                    write-debug "Value of adfsSchemaSetVar.IsCompiled: $($global:adfsSchemaSetVar.IsCompiled)"
                    write-debug "Compiation Done - continue execution"          
                }
            }
            write-debug "Stopping SchemaLoaderSopwatch"
            $SchemaLoaderStopWatch.Stop()
            write-debug "Loading schemas finished. TotalTime: $($SchemaLoaderStopWatch.Elapsed.ToString())"  
            write-debug "Returning XML Schema SET" 
            write-debug "Closing SchemaReaders"
            $schemaReader.Close()
            $schemaReader2.Close()
            $schemaReader3.Close()
            $schemaReader4.Close()
            Write-debug "EXITING: Add-SPMetadataSchemas"
        } 
    }
    else 
    {
        Write-debug "adfsSchemaSetVar existed. Nothing to do"
        write-debug "Closing Schema init."
        Write-debug "EXITING: Add-SPMetadataSchemas"
    }  
}#End Add-SPMetadataSchemas
function Get-MetadataCertificates
{
    param (
        [ValidateNotNullOrEmpty()][xml]$XML
    )
    write-debug "ENTERED:Get-MetadataCertificates"
    Write-debug "Preparing Results table and helper class"
    class CertValidationClass
    {
        [string]$use
        [string]$data
        [int]$index
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$certDetails
    }
    $certTests = New-Object System.Collections.Hashtable
    Write-debug "Checking if ValidationError has been captured"
    if($script:ValidationError -eq $true)
    {
        Write-debug "Detected Validation Error. Throwing Exception"
        throw "Validation Error has been found! Cannot continue validating certificates"
    }
    Write-debug "Checked Validation Errors."
    Write-debug "Check argument XML"
    Write-debug "$($XML)"
    $parsed = [xml]$XML
    Write-debug "Checking XML Tags..."
    Write-debug "Running KeyDescriptor tag test..."
    if($null -ne $parsed.EntityDescriptor.SPSSODescriptor.KeyDescriptor)
    {
        Write-debug "First Check for KeyDescriptor success" 
        $certTests["KeyDescriptor"] = $true
    }
    else 
    {
        Write-debug "First Check for KeyDescriptor failed" 
    }
    Write-debug "Running SPSSODecriptor tag test..."
    if($parsed.ChildNodes.spssodescriptor.InnerXml -match "x509certificate")
    {
        write-debug "spssodescriptor innerXML check succeeded"
        $certTests["InnerXMLSPSSdescriptor"] = $true
    }
    else 
    {
        write-debug "spssodescriptor innerXML check failed"
        $certTests["InnerXMLSPSSdescriptor"] = $false
    }
    Write-debug "Running innerXML general tag test..."
    if($parsed.InnerXML -match "x509Certificate")
    {
        Write-debug "x509MarkCheck Succeeded"
        $certTests["InnerXMLGeneral"] = $true
    }
    else 
    {
        Write-debug "x509MarkCheck Failed"
        $certTests["InnerXMLGeneral"] = $false
    }
    Write-debug "Finished XML tests"
    Write-debug "Check certTests results"
    $results = @()
    if($certTests.ContainsValue($true) -eq $true)
    {
        write-debug "X509 certificate is most possbily found. Tests has been successful."
        $enc = [system.Text.Encoding]::ASCII
        for($i = 0; $i -lt $parsed.EntityDescriptor.SPSSODescriptor.KeyDescriptor.Length; $i++)
        {
            Write-debug "trying to parse certificates"
            $temp = New-object CertValidationClass
            $temp.index = $i
            $temp.use = $parsed.EntityDescriptor.SPSSODescriptor.KeyDescriptor[$i].use  
            $temp.data = $parsed.EntityDescriptor.SPSSODescriptor.KeyDescriptor[$i].KeyInfo.X509Data.x509Certificate
            $string = $temp.data
            write-debug "$($temp.data)"
            $data = $enc.GetBytes($string)
            try 
            {
                $temp.certDetails = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($data)
                write-debug "$($temp.certDetails)"
                $results += $temp
                if($temp.certDetails.NotAfter -lt (get-date))
                {
                    write-debug "Certificate is expired"
                    write-debug "Cert NotAfter:$($temp.certDetails.NotAfter)"
                    $msg = "Certificate usage: $($temp.use)`n$($temp.certDetails.Thumbprint) is expired. Expired on: $($temp.certDetails.NotAfter)"
                    [System.Windows.Forms.MessageBox]::Show($msg,"$($temp.use) certificate is expired",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error) 
                }
                elseif (($temp.certDetails.NotAfter -ge (get-date)) -and ($temp.certDetails.NotAfter -le (get-date).AddMonths(3))) 
                {
                    write-debug "Certificate is valid but will expire within 3 months"
                    write-debug "Cert NotAfter:$($temp.certDetails.NotAfter)"
                    $msg = "Certificate usage: $($temp.use)`n$($temp.certDetails.Thumbprint) is valid. Valid till: $($temp.certDetails.NotAfter).Going to expire soon"
                    [System.Windows.Forms.MessageBox]::Show($msg,"$($temp.use) certificate is valid",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) 
                }
                else 
                {
                    write-debug "Certificate is valid"
                    write-debug "Cert NotAfter:$($temp.certDetails.NotAfter)"
                    $msg = "Certificate usage: $($temp.use)`n$($temp.certDetails.Thumbprint) is valid. Valid till: $($temp.certDetails.NotAfter)"
                    [System.Windows.Forms.MessageBox]::Show($msg,"$($temp.use) certificate is valid",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)   
                }
            }
            catch 
            {
                Write-debug "Cert validation failed!"
                write-debug "EXCEPTION: $($_)"
                throw "Certificate validation failed"
            }
        }
        write-debug "Certificates has been parsed"
        write-debug "returning certificate validation results"
    }
    write-debug "EXIT: Get-MetadataCertificates"
}###end Get-metadataCertificates
####End helper functions
####helper strings
$script:EXecutionTime = "Execution Time:"
$Label1Text = "Simple Script to analyze if provided SP (service provider) SAML metadata is correct and contains required data.`nIt DOES NOT checks if provided URL's,id's or xml paramters values are correct. It checks only syntax of XML and SAML metadata schema.`nFirst you need to select XML in order to be able to click Validate"

#### Main GUI

$Form                            = New-Object system.Windows.Forms.Form
$Form.ClientSize                 = New-Object System.Drawing.Point(830,236)
$Form.text                       = "SP Metadata Validator version: $($script:versionDetails)"
$Form.TopMost                    = $false
$Form.FormBorderStyle            = [System.Windows.Forms.FormBorderStyle]::FixedSingle

$XMLPathTxt                        = New-Object system.Windows.Forms.TextBox
$XMLPathTxt.multiline              = $false
$XMLPathTxt.Text                   = "Path to XML File"
$XMLPathTxt.width                  = 785
$XMLPathTxt.height                 = 20
$XMLPathTxt.location               = New-Object System.Drawing.Point(11,85)
$XMLPathTxt.Font                   = New-Object System.Drawing.Font('Microsoft Sans Serif',8)

$Label1                          = New-Object system.Windows.Forms.Label
$Label1.text                     =  $Label1Text
$Label1.AutoSize                 = $true
$Label1.width                    = 25
$Label1.height                   = 10
$Label1.location                 = New-Object System.Drawing.Point(11,19)
$Label1.Font                     = New-Object System.Drawing.Font('Microsoft Sans Serif',8)

$LabelTime                          = New-Object system.Windows.Forms.Label
$LabelTime.text                     =  "$script:EXecutionTime"
$LabelTime.AutoSize                 = $true
$LabelTime.width                    = 25
$LabelTime.height                   = 10
$LabelTime.location                 = New-Object System.Drawing.Point(11,130)
$LabelTime.Font                     = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$Label2                          = New-Object system.Windows.Forms.Label
$Label2.text                     = "Path to XML SP metadata:"
$Label2.AutoSize                 = $true
$Label2.width                    = 25
$Label2.height                   = 10
$Label2.location                 = New-Object System.Drawing.Point(11,65)
$Label2.Font                     = New-Object System.Drawing.Font('Microsoft Sans Serif',8)

$ValidateBtn                         = New-Object system.Windows.Forms.Button
$ValidateBtn.text                    = "Validate XML"
$ValidateBtn.width                   = 96
$ValidateBtn.height                  = 30
$ValidateBtn.Enabled                 = $false
$ValidateBtn.location                = New-Object System.Drawing.Point(728,183)
$ValidateBtn.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$CloseBtn                               = New-Object system.Windows.Forms.Button
$CloseBtn.text                          = "Close"
$CloseBtn.width                         = 60
$CloseBtn.height                        = 30
$CloseBtn.location                      = New-Object System.Drawing.Point(11,183)
$CloseBtn.Font                          = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$HelpBtn                                = New-Object system.Windows.Forms.Button
$HelpBtn.text                           = "Help"
$HelpBtn.Enabled                        = $true
$HelpBtn.width                          = 60
$HelpBtn.height                         = 30
$HelpBtn.location                       = New-Object System.Drawing.Point(11,153)
$HelpBtn.Font                           = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$LoadSchemasBtn                         = New-Object system.Windows.Forms.Button
$LoadSchemasBtn.text                    = "Reload Schemas"
$LoadSchemasBtn.width                   = 120
$LoadSchemasBtn.height                  = 30
$LoadSchemasBtn.Enabled                 = $true
$LoadSchemasBtn.location                = New-Object System.Drawing.Point(600,183)
$LoadSchemasBtn.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',10)

$CertificatesBtn                         = New-Object system.Windows.Forms.Button
$CertificatesBtn.text                    = "Check metadata Certs"
$CertificatesBtn.width                   = 120
$CertificatesBtn.height                  = 30
$CertificatesBtn.Enabled                 = $false
$CertificatesBtn.location                = New-Object System.Drawing.Point(600,148)
$CertificatesBtn.Font                    = New-Object System.Drawing.Font('Microsoft Sans Serif',8)

$checkbox1                               = new-object System.Windows.Forms.checkbox
$checkbox1.Location                      = new-object System.Drawing.Point(89,143)
$checkbox1.Size                          = new-object System.Drawing.Size(250,50)
$checkbox1.Text                          = "Validate certificates if present in metadata"
$checkbox1.Checked                       = $false
$checkbox1.Font                          = New-Object System.Drawing.Font('Microsoft Sans Serif',8)

$ProgressBar1                           = New-Object system.Windows.Forms.ProgressBar
$ProgressBar1.width                     = 489
$ProgressBar1.height                    = 32
$ProgressBar1.Value                     = 0
$ProgressBar1.Maximum                   = 100
$ProgressBar1.location                  = New-Object System.Drawing.Point(89,183)

$Form.controls.AddRange(@($XMLPathTxt,$Label1,$Label2,$LabelTime,$ValidateBtn,$CloseBtn,$LoadSchemasBtn,$ProgressBar1,$checkbox1,$HelpBtn))

$ErrorProvider1                  = New-Object system.Windows.Forms.ErrorProvider
$ErrorProvider1.BlinkStyle = [System.Windows.Forms.ErrorBlinkStyle]::NeverBlink
##gui helper strings"
$rldSchTxt = "This operation may take up to 10 minutes.`n It's used to reninitilize xml schemas when encoutering issues with the XML validator`nDo you want to Continue?"
$msgBoxTxt = "It seems that the script has been run for the first time!`nFirst Time can take up two 10 minutes to initilize XML schemas.`nDo you want to continue?"

$XMLPathTxt.Add_Click({
    write-debug "ENTERED: XMLPathTxt.Add_Click"
    Write-debug "Cleaning Validation Error"
    $script:ValidationError = $false
    $ErrorProvider1.SetError($XMLPathTxt,"")
    write-debug "Clearing progress bar"
    $ProgressBar1.value = 0
    Write-debug "Cleaning XMLPathTxt Field Content"
    $XMLPathTxt.Clear()
    write-debug "OPENING - Open File Picker"
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = $ENV:USERPROFILE
    $OpenFileDialog.filter = "XML files (*.XML)|*.XML|All files (*.*)|*.*"
    $OpenFileDialog.Title = "Select SP metadata XML File"
    $OpenFileDialog.ShowDialog() | Out-Null 
    write-debug "SELECTED: $($OpenFileDialog.filename)"
    write-debug "$($OpenFileDialog.filename)"
    if($OpenFileDialog.filename -eq "")
    {
        Write-Debug "NO SELECTION MADE"
        $ValidateBtn.Enabled = $false
    }
    else
    {
        $XMLPathTxt.Text = $OpenFileDialog.filename
        $ValidateBtn.Enabled = $true
    }   
})

$ValidateBtn.Add_Click({
    write-debug "ENTERED: ValidateBtn.Add_Click"
    Write-Debug "Restoring default LabelTime value"
    $LabelTime.Text= $script:EXecutionTime
    $LabelTime.Refresh()
    write-debug "Testing SP Metadata File..."
    write-debug "Clearing ProgressBar"
    $ProgressBar1.Value=0
    write-debug "current ValidationErrorValue :$($script:ValidationError)"
    write-debug "OBSOLETE current envInitialized :$($global:adfsEnvInitialized)"
    write-debug "Incremeting ProgressBar"
    $progressBar1.Increment(10)
    write-debug "Checking if script has validationerrors before if yes then prompt message about some errors (possible schemas)"
    write-debug "VALUE value of script:ValidationError: $($script:ValidationError)"
    if($script:ValidationError -ne $true)
    {
        Write-debug "Checking if script has been initilized..."
        if($global:adfsSchemaSetVar -eq $null)
        { 
            Write-debug "Script has not been initilized. Prompting user..."
            $progressBar1.Increment(20)
            $msgBox = [System.Windows.Forms.MessageBox]::Show($msgBoxTxt,"Continue?",[System.Windows.Forms.MessageBoxButtons]::YesNo) 
            Write-debug "User selected:$($msgBox)"
        }
        else 
        {
            Write-debug "Value of adfsSchemaSetVar: $($global:adfsSchemaSetVar)"
        }
        if(($msgBox -eq "YES") -or ($global:adfsSchemaSetVar  -ne $null)) 
        {
            write-debug "Running parameter:$($XMLPathTxt.Text)"
            try {
                $progressBar1.Increment(30)
                Write-debug "Check CheckCerts Value"
                Write-debug "VALUE of CheckCerts:$($CheckCerts)"
                if ($script:CheckCerts) 
                {
                    $progressBar1.Increment(45)
                    Write-debug "CheckCerts require checking of certificates"
                    write-debug "Running TestSPMetadataFile with CheckCertificates switch"
                    $testResult = Test-SpMetadataFile -MetadataXML $XMLPathTxt.Text -CheckCertificates
                }
                else 
                {
                    $progressBar1.Increment(45)
                    write-debug "Running TestSPMetadataFile without CheckCertificates switch"
                    $testResult = Test-SpMetadataFile -MetadataXML $XMLPathTxt.Text
                }
                $progressBar1.Increment(90)
                if($testResult.TestPassed -eq $false )
                {
                    $ErrorProvider1.SetError($XMLPathTxt,"Metadata file is not correct!")
                    [System.Windows.Forms.MessageBox]::Show($testResult.Issues,"Found Errors in the Metadata",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Warning) 
                    $script:ValidationError = $true
                    $progressBar1.Increment(100)                
                }
                else 
                {
                    $ErrorProvider1.SetError($XMLPathTxt,"")
                    $progressBar1.Increment(100)
                    [System.Windows.Forms.MessageBox]::Show("Metadata Test passed: $($testResult.TestPassed)","No Errors in Metadata",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Information)
                    $script:ValidationError = $false
                }
            }
            catch 
            {
                $ProgressBar1.Increment(100)
                write-debug "Metadata test existance check exception caught"
                write-debug "Exception catched: $($_.Exception.Message)"
                if($_.Exception.Message -eq "SchemaFilesAreMissing")
                {
                    [System.Windows.Forms.MessageBox]::Show("Schemas Files Error:`n$($_.Exception.Message)","SchemasNotFound",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
                    $ValidateBtn.Enabled = $false                
                }
                else 
                {
                    [System.Windows.Forms.MessageBox]::Show("$($_.Exception.Message)","Metadata error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
                    $ValidateBtn.Enabled = $false
                    $ErrorProvider1.SetError($XMLPathTxt,"$($_.Exception.Message)")
                }
                $script:ValidationError = $true        
            }        
        }
        else 
        {
            write-debug "Clearing progress bar due to user's input"
            $progressBar1.Value = 0
        }   
    }
    else
    {
        write-debug "VALIDATION ERRORS OCCURED. skiping execution of validation"
        $progressBar1.Value = 0
        [System.Windows.Forms.MessageBox]::Show("Cannot process Validation. Script contains validation errors.","Script error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
    }
    write-debug "EXIT:ValidateBtn.Add_Click"
})

$CloseBtn.Add_Click({
    Write-Debug "ENTERED: CloseBtn.Add_Click"
    Write-Debug "Showing communication"
    $msgBox = [System.Windows.Forms.MessageBox]::Show("Do you want to Close the script?","Close?",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question) 
    write-debug "UserChoise: $($msgBox)"
    if($msgBox -eq "YES")
    {
        Write-Debug "SELECTED YES - CLOSING"
        write-debug "RESTORING VALUES: ErrorActionPreference"
        $ErrorActionPreference = $EABackup 
        $Form.Close() | Out-Null
    }
    else
    {
        write-debug "SELECTED Cancel - Execution"
    }
})

$HelpBtn.Add_Click({
    Write-Debug "ENTERED: HelpBtn.Add_Click"
    Write-debug "Opening notepad with readme file"
    try 
    {
        C:\WINDOWS\system32\notepad.exe "$($script:HelpFile)\readme.txt"
    }
    catch 
    {
        write-debug "$_"
    }
    Write-Debug "EXITING: HelpBtn.Add_Click"
})

$checkbox1.Add_CheckStateChanged({
    Write-Debug "ENTERED: Checkbox1 Event CheckState Changed"
    Write-Debug "Initializing variable"
    if($checkbox1.Checked -eq $true)
    {
        Write-debug "Setting CheckCerts to True"
        $script:CheckCerts = $true
    }
    else 
    {
        Write-debug "Setting CheckCerts to false"
        $script:CheckCerts = $false
    }
    Write-Debug "EXITING: Checkbox1 Event CheckState Changed"
})

$LoadSchemasBtn.Add_Click({
    Write-debug "ENTERED: LoadSchemasBtn.Add_Click"
    Write-debug "Prmopting User's input"
    $rldSch = [System.Windows.Forms.MessageBox]::Show($rldSchTxt,"Reload Schemas",[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Question) 
    write-debug "current ValidationErrorValue :$($script:ValidationError)"
    write-debug "OBSOLETE current envInitialized :$($global:adfsEnvInitialized)"
    write-debug "Incremeting ProgressBar"
    $progressBar1.Increment(10)
    write-debug "User Selection: $($rldSch)"
    if($rldSch -eq "YES")
    {
        Write-debug "Invoking Add-SPMetadataSchemas with reloadSchemas only"
        $progressBar1.Increment(20)
        $Form.UseWaitCursor = $true
        try 
        {
            Add-SPMetadataSchemas -reloadSchemas
            $Form.UseWaitCursor = $false
            $progressBar1.Increment(100)
            [System.Windows.Forms.MessageBox]::Show("Loading finished","Reload Schemas",[System.Windows.Forms.MessageBoxButtons]::OK) 
        }
        catch 
        {
            write-debug "Catched Add-SPMetadataSchemas exception"
            if($_.Exception.Message -eq "SchemaFilesAreMissing")
            {
                write-debug "Catched SchemaFilesAreMissing in LoadSchemasBtn "
                [System.Windows.Forms.MessageBox]::Show("Schemas Files Error:`n$($_.Exception.Message)","SchemasNotFound",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
                $ValidateBtn.Enabled = $false
                $Form.UseWaitCursor = $false
                $script:ValidationError= $true
            }
            else
            {
                write-debug "Different Error has been catched in LoadSchemasBtn"
                [System.Windows.Forms.MessageBox]::Show("Schemas Files Error:`n$($_.Exception.Message)","Schemas Loading Error",[System.Windows.Forms.MessageBoxButtons]::OK,[System.Windows.Forms.MessageBoxIcon]::Error)
                $script:ValidationError= $true
                $Form.UseWaitCursor = $false 
            }
        }        
    }
    else 
    {
        write-debug "User selected $($rldSch) - exiting"
        $progressBar1.Value = 0
    }
    $progressBar1.Value = 0
    Write-debug "EXITING: LoadSchemasBtn.Add_Click"
})

write-debug "ENTERED: Showing Form XMLValidator"
write-debug "SCRIPT PATH:$($MyInvocation.MyCommand.Path)"
$script:xsdFilesPath = (split-path $MyInvocation.MyCommand.Path) + "\schemas"
$script:HelpFile = split-path $MyInvocation.MyCommand.Path
$Form.ShowDialog() | Out-Null
write-debug "RESTORING VALUES: ErrorActionPreference"
$ErrorActionPreference = $EABackup 
Write-debug "EXITING: script"