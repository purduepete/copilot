function Get-MachineClass {
    param([string]$ComputerName = $env:COMPUTERNAME)

    if ($ComputerName -like 'XFINJIMB*' -or $ComputerName -like 'CPC-jimb-*') { return 'work' }
    if ($ComputerName -like 'JIMBROWN*') { return 'home' }
    return $null
}
