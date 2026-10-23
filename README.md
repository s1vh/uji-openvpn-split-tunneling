# OpenVPN UJI — Split tunneling para Windows

Configuración alternativa de **OpenVPN Connect para Windows** que permite acceder a direcciones de la red de la **Universitat Jaume I (UJI)** a través de la VPN, conservando la salida doméstica para el resto del tráfico IPv4.

El proyecto surgió el **23 de octubre de 2026**, durante unas pruebas de conectividad tras la restricción temporal de acceso externo a varios servicios de la UJI motivada por alertas sobre vulnerabilidades críticas de PHP. Es un trabajo **independiente y no oficial**; no sustituye las instrucciones ni las políticas de acceso de la universidad.

## Archivos

- [`OpenVPN_UJI_split-tunneling.ovpn`](./OpenVPN_UJI_split-tunneling.ovpn): perfil probado en OpenVPN Connect 3.9.0 para Windows (derivado del perfil de conexión UJI).
- [`docs/informe.md`](./docs/informe.md): descripción técnica del problema, pruebas, solución y limitaciones.
- [`tools/metric_corrections.ps1`](./tools/metric_corrections.ps1): herramienta auxiliar para corregir manualmente la métrica **de la ruta predeterminada** de la VPN. **No es necesaria** al utilizar el perfil anterior en el entorno probado.

## Qué cambia el perfil

```ovpn
route-nopull
route-metric 100
route 150.128.0.0 255.255.0.0
```

- `route-nopull` evita aceptar rutas y opciones DNS enviadas por el servidor.
- `route-metric 100` eleva la métrica de las rutas creadas para el túnel; en la combinación probada de OpenVPN Connect y Windows también afectó a la ruta predeterminada que Windows instalaba en el adaptador TAP.
- La ruta `150.128.0.0/16` mantiene el acceso a la red universitaria.

El perfil conserva la autenticación de usuario, la comprobación del certificado TLS del servidor y el material público de CA del perfil original. **No contiene usuario, contraseña, claves privadas ni tokens de sesión.**

## Uso

1. Necesitas autorización para utilizar la VPN de la UJI y OpenVPN Connect en Windows.
2. Importa [`OpenVPN_UJI_split-tunneling.ovpn`](./OpenVPN_UJI_split-tunneling.ovpn) como **perfil independiente**; conserva el oficial sin modificar.
3. Conecta y completa cualquier verificación de identidad que solicite el servicio.
4. Comprueba la ruta efectiva desde PowerShell **sin privilegios elevados**:

   ```powershell
   Find-NetRoute -RemoteIPAddress 1.1.1.1 |
       Where-Object DestinationPrefix |
       Format-Table DestinationPrefix,NextHop,InterfaceAlias

   Find-NetRoute -RemoteIPAddress 150.128.98.10 |
       Where-Object DestinationPrefix |
       Format-Table DestinationPrefix,NextHop,InterfaceAlias
   ```

   En el entorno probado, el primer destino salía por `Wi-Fi` y el segundo por `Local Area Connection` (TAP de OpenVPN).

## Compatibilidad y límites

- **Probado:** Windows, OpenVPN Connect **3.9.0** / OpenVPN core **3.11.3**, con una conexión doméstica cuya métrica efectiva era inferior a la de la VPN. No se ha probado con todos los clientes, plataformas ni redes.
- **No es un bloqueo absoluto de tráfico:** la ruta predeterminada de la VPN permanece instalada con métrica superior. Si desaparece o empeora la ruta doméstica, el tráfico general podría pasar por la VPN. **No equivale a una política de aislamiento ni a un kill switch.**
- El encaminamiento es **por IP**, no por dominio. Servicios UJI alojados fuera de `150.128.0.0/16` pueden usar la conexión doméstica.
- No se configura split DNS adicional: en las pruebas, los DNS domésticos resolvían los servicios públicos evaluados y la política NRPT temporal de OpenVPN se retiraba al desconectar. No está garantizada la resolución de todos los recursos internos.
- La ruta `/32` hacia el servidor VPN fue observada por Wi-Fi; su presencia debe revisarse tras cambios de red o cliente.
- El script auxiliar requiere **PowerShell como administrador**, modifica rutas activas y pide confirmación. No hay que ejecutarlo si el perfil ya hace correctamente el split tunneling.

Más información y evidencias en el [informe técnico](./docs/informe.md).

## Referencias

- [Manual de OpenVPN 2.6](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html)
- [CERT-EU — Critical Vulnerabilities in PHP, 2026-018](https://cert.europa.eu/publications/security-advisories/2026-018)

> Antes de redistribuir un perfil derivado de la configuración oficial de terceros, comprueba que su publicación sea compatible con las condiciones aplicables. Este repositorio no está afiliado a la UJI ni a OpenVPN.
