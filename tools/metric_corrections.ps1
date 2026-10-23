# Localizar la ruta universitaria
$uji = Get-NetRoute -AddressFamily IPv4 `
    -DestinationPrefix "150.128.0.0/16" `
    -PolicyStore ActiveStore |
    Where-Object InterfaceAlias -eq "Local Area Connection"

# Localizar exclusivamente la ruta predeterminada de esa VPN
$vpnDefault = @(
    Get-NetRoute -AddressFamily IPv4 `
        -DestinationPrefix "0.0.0.0/0" `
        -PolicyStore ActiveStore |
    Where-Object {
        $_.InterfaceIndex -eq $uji.InterfaceIndex -and
        $_.NextHop -eq $uji.NextHop
    }
)

if ($vpnDefault.Count -ne 1) {
    throw "No se ha identificado una única ruta VPN."
}

# Comprobar antes de modificar
$vpnDefault | Format-Table DestinationPrefix, NextHop,
    InterfaceAlias, RouteMetric

# Confirmar el cambio
Set-NetRoute -DestinationPrefix "0.0.0.0/0" `
    -InterfaceIndex $uji.InterfaceIndex `
    -NextHop $uji.NextHop `
    -PolicyStore ActiveStore `
    -RouteMetric 100 -Confirm