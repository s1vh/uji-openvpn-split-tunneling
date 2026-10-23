# Informe técnico — Split tunneling de OpenVPN para la UJI

**Fecha de las pruebas:** 23 de octubre de 2026  
**Entorno:** Windows, OpenVPN Connect 3.9.0 (OpenVPN core 3.11.3, adaptador TAP)  
**Ámbito:** encaminamiento IPv4, resolución DNS y comportamiento de IPv6 del cliente  
**Carácter:** análisis independiente del lado cliente; no es documentación oficial de la UJI.

## 1. Contexto y objetivo

La UJI restringió temporalmente el acceso externo a determinados servicios, a raíz de alertas por vulnerabilidades críticas de PHP. Como referencia pública del contexto, CERT-EU publicó el aviso **2026-018** el 21 de octubre de 2026, recomendando parchear y, cuando fuera necesario, aislar servicios expuestos a Internet. La motivación de las pruebas fue disponer de acceso autorizado a servicios universitarios sin redirigir por la VPN toda la navegación ajena a la universidad.

**Objetivo técnico:** utilizar el túnel para destinos de la red `150.128.0.0/16` y mantener como salida predeterminada la conexión doméstica, sin debilitar la validación TLS del servidor.

Se conservaron los perfiles originales durante las pruebas; las modificaciones se importaron como perfiles independientes. No se realizaron cambios en sistemas de la universidad.

## 2. Problema inicial

El perfil original incluía `redirect-gateway def1`, por lo que Windows instalaba rutas `0.0.0.0/1` y `128.0.0.0/1`, desviando la salida IPv4 general por el túnel. Este comportamiento era innecesario para el caso de uso y podía afectar a servicios externos y a la navegación cotidiana.

Al introducir `route-nopull` y una ruta explícita `150.128.0.0/16`, desaparecieron esas rutas `/1`, pero **persistía una ruta predeterminada `0.0.0.0/0` asociada al adaptador VPN**. En el cliente probado, OpenVPN recibía una configuración `ifconfig` con máscara `0.0.0.0` y puerta de enlace VPN; Windows instalaba una ruta predeterminada adicional al configurar el TAP.

Antes de la corrección, la tabla de rutas incluía:

| Prefijo | Interfaz | Next hop | Métrica de ruta | Métrica de interfaz |
|---|---|---|---:|---:|
| `0.0.0.0/0` | Local Area Connection (VPN) | `150.128.126.1` | 1 | 1 |
| `0.0.0.0/0` | Wi-Fi | `192.168.1.1` | 0 | 30 |
| `150.128.0.0/16` | Local Area Connection (VPN) | `150.128.126.1` | 256 | 1 |

La ruta predeterminada VPN, con métrica efectiva `2`, prevalecía sobre la doméstica, con métrica efectiva `30`.

**Nota:** las direcciones de interfaz y puerta de enlace del túnel variaron entre sesiones; no deben fijarse permanentemente en scripts.

## 3. Diagnóstico y pruebas intermedias

### 3.1 Configuración del túnel y cifrado

Se conservó `cipher AES-256-GCM`, con negociación confirmada por el registro del cliente; una versión experimental que lo había omitido no establecía correctamente la conexión. Las conexiones exitosas verificaron el certificado del servidor `vpn.uji.es` mediante TLS y las comprobaciones existentes del perfil.

Se mantuvieron `auth-user-pass`, `auth-nocache`, `remote-cert-tls server` y `verify-x509-name`. La directiva `setenv CLIENT_CERT 0` permitió importar el perfil en OpenVPN Connect sin exigir un certificado cliente que el esquema de autenticación universitario no proporcionaba.

### 3.2 Eliminación manual de la ruta

Se probó `Remove-NetRoute` sobre **solo** `0.0.0.0/0` de la interfaz VPN. En una sesión ya autorizada, la eliminación permitió inicialmente:

- `1.1.1.1` → Wi-Fi;
- `150.128.98.10` → adaptador VPN.

La eliminación no se adoptó como solución permanente: modifica externamente la configuración activa del cliente, exige privilegios elevados y no garantiza su estabilidad en las reconexiones. Un corte observado durante una sesión anterior coincidió con un error de transporte; el registro no permite demostrar que la eliminación de la ruta fuera su causa.

### 3.3 Excepción hacia el servidor OpenVPN

En una sesión, la conexión TCP al servidor utilizó una dirección local doméstica (`192.168.1.222`) y destino `150.128.197.72:1194`. La tabla contenía una excepción:

```text
150.128.197.72/32  -> 192.168.1.1  (Wi-Fi)
150.128.0.0/16     -> 150.128.126.1 (VPN)
```

La excepción `/32` es más específica que `/16` y evita enviar el transporte de esa sesión hacia el propio túnel. Se observó en el cliente utilizado; no debe suponerse idéntico comportamiento en todas las implementaciones.

## 4. Solución: perfil v4

El cambio funcional se reduce a tres directivas:

```ovpn
route-nopull
route-metric 100
route 150.128.0.0 255.255.0.0
```

`route-nopull` evita la instalación de rutas y parámetros DNS enviados mediante `PUSH`; `route` define explícitamente el bloque universitario; `route-metric 100` asigna la métrica seleccionada. Aunque el manual de OpenVPN documenta `route-metric` como valor predeterminado para las rutas, en este entorno concreto OpenVPN Connect 3 también lo trasladó a la configuración de la puerta de enlace del adaptador Windows.

### Resultado sin intervención manual posterior

| Prefijo | Interfaz | Next hop | Métrica de ruta | Métrica de interfaz | Métrica efectiva |
|---|---|---|---:|---:|---:|
| `0.0.0.0/0` | Wi-Fi | `192.168.1.1` | 0 | 30 | **30** |
| `0.0.0.0/0` | VPN | `150.128.126.1` | 100 | 1 | **101** |
| `150.128.0.0/16` | VPN | `150.128.126.1` | 100 | 1 | **101** |

La selección de rutas de Windows dio los resultados esperados:

```text
Find-NetRoute 1.1.1.1       -> 0.0.0.0/0       -> 192.168.1.1     -> Wi-Fi
Find-NetRoute 150.128.98.10 -> 150.128.0.0/16  -> 150.128.126.1   -> VPN
```

Se repitieron las consultas tras un intervalo y se mantuvo la misma selección de rutas. La ruta universitaria `/16` prevalece para sus destinos por ser más específica, independientemente de que su métrica efectiva sea `101`.

**Interpretación:** se verificó la decisión de encaminamiento de Windows para ambos destinos. No se efectuó una captura de paquetes completa ni se auditó el comportamiento de todas las aplicaciones.

## 5. DNS e IPv6

Con el perfil v4 conectado:

- Los resolutores IPv4 visibles siguieron siendo `8.8.8.8` y `8.8.4.4` en Wi-Fi; no apareció `150.128.98.10` como DNS del adaptador VPN.
- La NRPT de Windows mostraba una regla temporal `OpenVPNDNSRouting-9956`, con espacio de nombres `.` y **sin servidores DNS declarados**. En esa misma configuración, las resoluciones estándar se realizaron correctamente.
- `Resolve-DnsName example.com -Type A -DnsOnly` y `-Type AAAA -DnsOnly` devolvieron respuestas válidas.
- `Resolve-DnsName www.uji.es -Type A -DnsOnly` resolvió a un balanceador de AWS mediante los DNS habituales; esto muestra que algunos servicios públicos de la universidad se alojan fuera del bloque `150.128.0.0/16`.
- `Find-NetRoute` para `2606:4700:4700::1111` seleccionó `::/0` por Wi-Fi, con puerta de enlace `fe80::1`.
- Después de desconectar OpenVPN, `Get-DnsClientNrptRule` no devolvió reglas `OpenVPNDNSRouting*`: la regla temporal se retiró.

Estas comprobaciones **no prueban** que todos los nombres internos de la UJI se resuelvan mediante DNS público, ni validan las preferencias DoH particulares de cada navegador. No se ha añadido split DNS específico porque no hizo falta para los servicios ensayados.

## 6. Script auxiliar de corrección manual

[`../tools/metric_corrections.ps1`](../tools/metric_corrections.ps1) identifica la ruta `150.128.0.0/16`, localiza la ruta predeterminada de la misma interfaz y puerta de enlace, comprueba que haya una única coincidencia y solicita confirmación para cambiar su métrica a `100` mediante `Set-NetRoute` en `ActiveStore`.

Sirve como apoyo de diagnóstico o recuperación para configuraciones en las que la métrica no se aplique correctamente. **No es necesario con la v4 en el entorno ensayado**. Debe ejecutarse con privilegios de administrador y revisarse la ruta identificada antes de confirmar. Preserva la lógica del script utilizado durante las pruebas; no constituye un instalador ni un mecanismo automático.

## 7. Limitaciones y riesgos operativos

1. **No es un aislamiento garantizado.** La ruta predeterminada del túnel no se elimina: permanece con métrica efectiva superior. Si la ruta doméstica desaparece o cambia su métrica, podría usarse la predeterminada de la VPN.
2. **Dependencia del entorno.** El valor `100` se ha validado en Windows con métricas domésticas concretas; una red diferente puede requerir revisión. OpenVPN Connect, OpenVPN Community y otros clientes no tienen por qué tratar todas las directivas de modo idéntico.
3. **Solo encaminamiento IPv4 selectivo.** IPv6 permaneció por Wi-Fi durante las pruebas. No se configuró una política IPv6 dentro del túnel.
4. **Cobertura por IP, no por dominio.** Los servicios universitarios alojados en proveedores externos pueden quedar fuera de `150.128.0.0/16`.
5. **Configuración dependiente de la universidad.** Cambios en el servidor VPN, en sus rutas o en las políticas de acceso pueden exigir revisar el perfil. Su utilización está supeditada a la autorización y normas de la UJI.
6. **Credenciales no retenidas.** `auth-nocache` evita su conservación por el cliente; ante ciertas reconexiones puede ser necesario introducirlas nuevamente.

## 8. Conclusión

En la configuración probada, el perfil v4 permitió establecer la VPN UJI, conservar las verificaciones TLS originales y dirigir **la red universitaria por el túnel**, mientras que **la ruta predeterminada IPv4 y la salida IPv6 siguieron utilizando Wi-Fi**. La resolución de nombres públicos funcionó sin imponer el DNS universitario y la NRPT temporal desapareció al desconectar.

La solución basada en `route-metric 100` evitó tener que ejecutar scripts posteriores a cada conexión. Se propone como configuración **experimental, independiente y documentada**, no como sustituto universal del perfil oficial.

## 9. Referencias

- [OpenVPN 2.6 — Manual: `route-nopull`, `route-metric`, `auth-nocache`](https://openvpn.net/community-docs/community-articles/openvpn-2-6-manual.html)
- [OpenVPN 3 — Configuración TAP en Windows](https://github.com/OpenVPN/openvpn3/blob/master/openvpn/tun/win/client/tunsetup.hpp)
- [CERT-EU, Security Advisory 2026-018: Critical Vulnerabilities in PHP](https://cert.europa.eu/publications/security-advisories/2026-018)

**Trazabilidad:** las tablas y ejemplos de salida proceden de pruebas manuales y registros locales obtenidos el 23/10/2026; se han omitido nombres de usuario, identificadores de cuenta y otros elementos innecesarios para reproducir el análisis.
