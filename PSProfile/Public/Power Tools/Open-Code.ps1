function Open-Code {
    <#
    .SYNOPSIS
    A drop-in replacement for the Visual Studio Code CLI `code`. Allows tab-completion of GitPath aliases if ProjectPaths are filled out with PSProfile that expand to the full path when invoked.

    .DESCRIPTION
    A drop-in replacement for the Visual Studio Code CLI `code`. Allows tab-completion of GitPath aliases if ProjectPaths are filled out with PSProfile that expand to the full path when invoked.

    .PARAMETER Path
    The path of the file or folder to open with Code. Allows tab-completion of GitPath aliases if ProjectPaths are filled out with PSProfile that expand to the full path when invoked.

    .PARAMETER Cookbook
    If you are using Chef and have your chef-repo folder in your GitPaths, this will allow you to specify a cookbook path to open from the Cookbooks subfolder.

    .PARAMETER AddToWorkspace
    If $true, adds the folder to the current Code workspace.

    .PARAMETER InputObject
    Pipeline input to display as a temporary file in Code. Temp files are automatically cleaned up after the file is closed in Code. No need to add the `-` after `code` to specify that pipeline input is expected.

    .PARAMETER Language
    The language or extension of the temporary file created from the pipeline input. This allows specifying a file type like 'powershell' or 'csv' or an extension like 'ps1', enabling opening of the temp file with the editor file language already set correctly.

    .PARAMETER Wait
    If $true, waits for the file to be closed in Code before returning to the prompt. If $false, opens the file using a background job to allow immediately returning to the prompt. Defaults to $false.

    .PARAMETER Arguments
    Any additional arguments to be passed directly to the Code CLI command, e.g. `Open-Code --list-extensions` or `code --list-extensions` will still work the same as expected.

    .EXAMPLE
    Get-Process | ConvertTo-Csv | Open-Code -Language csv

    Gets the current running processes, converts to CSV format and opens it in Code via background job as a CSV. Easy Out-GridView!

    .EXAMPLE
    def Update-PSProfileSetting | code -l ps1

    Using shorter aliases, gets the current function definition of the Update-PSProfileSetting function and opens it in Code as a PowerShell file to take advantage of immediate syntax highlighting.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    Param (
        [parameter(Mandatory,Position = 0,ParameterSetName = 'Path')]
        [parameter(Position = 0,ParameterSetName = 'InputObject')]
        [String]
        $Path,
        [parameter(ParameterSetName = 'Path')]
        [parameter(ParameterSetName = 'Cookbook')]
        [Alias('add','a')]
        [Switch]
        $AddToWorkspace,
        [parameter(ValueFromPipeline,ParameterSetName = 'InputObject')]
        [Object]
        $InputObject,
        [parameter(ParameterSetName = 'InputObject')]
        [Alias('l','lang','Extension')]
        [String]
        $Language = 'txt',
        [parameter(ValueFromPipeline,ParameterSetName = 'InputObject')]
        [Alias('w')]
        [Switch]
        $Wait,
        [parameter(ValueFromRemainingArguments)]
        [Object]
        $Arguments
    )
    DynamicParam {
        if ($global:PSProfile.GitPathMap.ContainsKey('chef-repo')) {
            $RuntimeParamDic = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary
            $ParamAttrib = New-Object System.Management.Automation.ParameterAttribute
            $ParamAttrib.Mandatory = $true
            $ParamAttrib.ParameterSetName = 'Cookbook'
            $AttribColl = New-Object System.Collections.ObjectModel.Collection[System.Attribute]
            $AttribColl.Add($ParamAttrib)
            $set = (Get-ChildItem (Join-Path $global:PSProfile.GitPathMap['chef-repo'] 'cookbooks') -Directory).Name
            $AttribColl.Add((New-Object System.Management.Automation.ValidateSetAttribute($set)))
            $AttribColl.Add((New-Object System.Management.Automation.AliasAttribute('c')))
            $RuntimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter('Cookbook',  [string], $AttribColl)
            $RuntimeParamDic.Add('Cookbook',  $RuntimeParam)
        }
        return  $RuntimeParamDic
    }
    Begin {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $collection = New-Object System.Collections.Generic.List[object]
            $extDict = @{
                txt        = 'txt'
                powershell = 'ps1'
                csv        = 'csv'
                sql        = 'sql'
                xml        = 'xml'
                json       = 'json'
                yml        = 'yml'
                csharp     = 'cs'
                fsharp     = 'fs'
                ruby       = 'rb'
                html       = 'html'
                css        = 'css'
                go         = 'go'
                jsonc      = 'jsonc'
                javascript = 'js'
                typescript = 'ts'
                less       = 'less'
                log        = 'log'
                python     = 'py'
                razor      = 'cshtml'
                markdown   = 'md'
            }
        }
    }
    Process {
        $code = (Get-Command code -All | Where-Object { $_.CommandType -notin @('Function','Alias') })[0].Source
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $collection.Add($InputObject)
        }
        else {
            $target = switch ($PSCmdlet.ParameterSetName) {
                Path {
                    if ($PSBoundParameters['Path'] -eq '.') {
                        $PWD.Path
                    }
                    elseif ($null -ne $global:PSProfile.GitPathMap.Keys) {
                        if ($global:PSProfile.GitPathMap.ContainsKey($PSBoundParameters['Path'])) {
                            $global:PSProfile.GitPathMap[$PSBoundParameters['Path']]
                        }
                        else {
                            $PSBoundParameters['Path']
                        }
                    }
                    else {
                        $PSBoundParameters['Path']
                    }
                }
                Cookbook {
                    [System.IO.Path]::Combine($global:PSProfile.GitPathMap['chef-repo'],'cookbooks',$PSBoundParameters['Cookbook'])
                }
            }
            if ($AddToWorkspace) {
                Write-Verbose "Running command: code --add $($PSBoundParameters[$PSCmdlet.ParameterSetName]) $Arguments"
                & $code --add $target $Arguments
            }
            else {
                Write-Verbose "Running command: code $($PSBoundParameters[$PSCmdlet.ParameterSetName]) $Arguments"
                & $code $target $Arguments
            }
        }
    }
    End {
        if ($PSCmdlet.ParameterSetName -eq 'InputObject') {
            $ext = if ($extDict.ContainsKey($Language)) {
                $extDict[$Language]
            }
            else {
                $Language
            }
            $in = @{
                StdIn   = $collection
                TmpFile = [System.IO.Path]::Combine(([System.IO.Path]::GetTempPath()),"code-stdin-$(-join ((97..(97+25) | ForEach-Object {[char]$_}) | Get-Random -Count 3)).$ext")
            }
            $handler = {
                Param(
                    [hashtable]
                    $in
                )
                try {
                    $code = (Get-Command code -All | Where-Object { $_.CommandType -notin @('Function','Alias') })[0].Source
                    $in.StdIn | Set-Content $in.TmpFile -Force
                    & $code $in.TmpFile --wait
                }
                catch {
                    throw
                }
                finally {
                    if (Test-Path $in.TmpFile -ErrorAction SilentlyContinue) {
                        Remove-Item $in.TmpFile -Force
                    }
                }
            }
            if (-not $Wait) {
                Write-Verbose "Piping input to Code: `$in | Start-Job {code -}"
                Start-Job -ScriptBlock $handler -ArgumentList $in
            }
            else {
                Write-Verbose "Piping input to Code: `$in | code -"
                .$handler($in)
            }
        }
    }
}

Register-ArgumentCompleter -CommandName Open-Code -ParameterName Path -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    Get-PSProfileArguments -WordToComplete "GitPathMap.$wordToComplete" -FinalKeyOnly
}

Register-ArgumentCompleter -CommandName Open-Code -ParameterName Language -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameter)
    @('txt','powershell','csv','sql','xml','json','yml','csharp','fsharp','ruby','html','css','go','jsonc','javascript','typescript','less','log','python','razor','markdown') | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}