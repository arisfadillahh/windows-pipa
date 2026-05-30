[CmdletBinding()]
param(
    [string] $Subnet = '192.168.1',
    [int] $Port = 22,
    [int] $TimeoutMs = 350
)

$ErrorActionPreference = 'Stop'

$items = foreach ($i in 1..254) {
    $ip = "$Subnet.$i"
    $client = [System.Net.Sockets.TcpClient]::new()
    $async = $client.BeginConnect($ip, $Port, $null, $null)
    [pscustomobject]@{
        IP = $ip
        Client = $client
        Async = $async
    }
}

Start-Sleep -Milliseconds $TimeoutMs

foreach ($item in $items) {
    if ($item.Async.IsCompleted -and $item.Client.Connected) {
        try {
            $item.Client.EndConnect($item.Async)
            $stream = $item.Client.GetStream()
            $stream.ReadTimeout = 800
            $buffer = New-Object byte[] 256
            $read = $stream.Read($buffer, 0, $buffer.Length)
            $banner = [Text.Encoding]::ASCII.GetString($buffer, 0, $read).Trim()
            [pscustomobject]@{
                IP = $item.IP
                Port = $Port
                Banner = $banner
            }
        } catch {
            [pscustomobject]@{
                IP = $item.IP
                Port = $Port
                Banner = ''
            }
        }
    }
    $item.Client.Close()
}

