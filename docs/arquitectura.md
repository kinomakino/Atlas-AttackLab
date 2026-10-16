# Arquitectura

Fecha: 2026-10-16. Estado: propuesta. Parte de [decisiones.md](decisiones.md) y del diseño de pantallas aprobado.

## Idea central

Un mismo **motor de labs** (paquete Python) se usa en dos sitios:

- **Online**, contra Azure OpenAI, detrás de la plataforma que gestiona usuarios y puntos.
- **En local**, contra Ollama, dentro del `docker compose` del alumno.

Un lab se escribe una sola vez y sirve para los dos.

## Plataforma online (Azure)

```
                  Internet
                     │
        ┌────────────▼─────────────┐
        │  web  (SvelteKit)        │   Container App · login integrado
        │  Login GitHub / Microsoft│   (Easy Auth de Container Apps)
        └────────────┬─────────────┘
                     │
        ┌────────────▼─────────────┐     ┌──────────────────┐
        │  api  (FastAPI)          │────▶│ PostgreSQL       │
        │  usuarios, progreso,     │     │ usuarios, intentos│
        │  flags, juez, puntos,    │     │ retos, puntos     │
        │  ranking, límites        │     └──────────────────┘
        └────────────┬─────────────┘     Key Vault: secreto de flags
                     │ red interna
        ┌────────────▼─────────────┐     ┌──────────────────┐
        │  runner  (motor de labs) │────▶│ Azure OpenAI     │
        │  sin base de datos,      │     │ filtro contenido │
        │  sin secretos de la      │     │ cuota por modelo │
        │  plataforma              │     └──────────────────┘
        └──────────────────────────┘
```

### Piezas

| Pieza | Qué hace | Por qué así |
|---|---|---|
| **web** | Las pantallas del diseño. SvelteKit, como roadmap-seguridad. | Mismo stack que ya usas. |
| **Login** | GitHub y Microsoft con la autenticación integrada de Container Apps. | Sin contraseñas ni código de login propio que mantener. |
| **api** | Lo único que toca la base de datos: perfil, progreso, intentos, puntos, ranking, límites. Genera la flag y hace de juez. | Toda la lógica de puntos en un solo sitio, en el servidor. |
| **runner** | Ejecuta el reto: monta el contexto del lab con la flag del jugador, llama al modelo y devuelve la respuesta y la traza. | Es lo que se ataca, así que va aislado. Si alguien lo rompe, no llega a usuarios ni puntos. |
| **PostgreSQL** | Datos de la plataforma. | Flexible Server B1ms basta para empezar. |
| **Key Vault** | Secreto para las flags y credenciales. | Acceso con identidad administrada, sin secretos en el código. |
| **Azure OpenAI** | El modelo de los retos. Un modelo "mini" (hoy gpt-4.1-mini o equivalente). | Pago por uso, filtro de contenido de Azure y cuotas. |
| **Monitor** | Logs, métricas y alertas (Log Analytics + Application Insights). | Para detectar trampas y abuso. |

### Cómo se juega un intento

1. El jugador envía un mensaje. La **api** comprueba la sesión y el límite diario.
2. La **api** calcula la flag del jugador: `HMAC(secreto, usuario + lab + modo)`. Es siempre la misma para él e imposible de adivinar para otro.
3. La **api** llama al **runner** por red interna con el lab, el modo, la conversación y la flag.
4. El **runner** monta el contexto, llama al modelo y aplica las defensas del modo protegido. Devuelve la respuesta y la traza.
5. La **api** hace de **juez**: si la flag del jugador aparece en la respuesta, aunque venga deformada, apunta el reto como resuelto y suma los puntos.
6. Todo intento queda registrado.

El navegador nunca envía puntos ni "lo he resuelto". Solo envía mensajes.

### Defensas de la propia plataforma

- **Límites:** intentos por usuario y día, mensajes y tokens máximos por intento, y peticiones por IP.
- **Alertas:** resoluciones imposiblemente rápidas, muchas cuentas desde la misma IP, la misma conversación ganadora en varias cuentas.
- **Runner sin acceso a nada:** sin red hacia la base de datos ni al Key Vault. Solo puede hablar con Azure OpenAI.
- **Cabeceras y cookies seguras**, CSRF, y CSP estricta en la web.
- **Más adelante:** Front Door con WAF delante, cuando haya tráfico que lo justifique.

### Coste mensual estimado

Supuesto: **1.000 jugadores activos al mes, 100 intentos cada uno** (100.000 intentos), unos 600 tokens de entrada y 150 de salida por intento. Precios de catálogo de Azure en euros, consultados el 2026-10-16.

| Recurso | Cálculo | €/mes |
|---|---|---|
| Azure OpenAI (gpt-4.1-mini) | 60 M tokens de entrada × 0,40 €/M + 15 M de salida × 1,40 €/M | ~45 |
| Container Apps: web + api | 1 réplica siempre encendida, 0,5 vCPU y 1 GiB (descontada la capa gratuita) | ~35 |
| Container Apps: runner | Escala a cero; solo cuando hay intentos | ~5 |
| PostgreSQL B1ms | 0,0175 €/h × 730 h + 32 GB de disco | ~17 |
| Log Analytics, Key Vault, registro | Logs moderados | ~15 |
| **Total** | | **~120 €** |

Con 100 jugadores ronda los 60–70 €, porque lo fijo pesa más que el modelo. Front Door con WAF sumaría ~30 € (Standard) o bastante más (Premium).

## Lab local (Docker)

```
compose.yaml  ── todo escucha en 127.0.0.1:8080
├── portal      la misma web en "modo local": sin login ni ranking,
│               progreso guardado en un volumen del alumno
├── runner      el mismo motor de labs, apuntando a Ollama
├── ollama      se baja los modelos la primera vez
└── servicios falsos por lab (ERP, correo, MCP, RAG…), con perfiles
    para arrancar solo los del lab que se juega
```

- **Redes:** los labs y los servicios falsos van en una red interna sin salida a internet. Solo `ollama` tiene salida, para descargar modelos.
- **Contenedores:** sin carpetas del anfitrión, sin privilegios, sistema de ficheros de solo lectura donde se pueda, usuario no root.
- **Publicación:** imágenes en GHCR firmadas con cosign desde GitHub Actions, con lista de componentes (SBOM).
- **GPU:** opcional, con la variable `OLLAMA_URL` apuntando a un Ollama propio.
- **Sin flags secretas:** en local el juez es el mismo, pero nada puntúa, así que no hace falta esconder nada.

## Estructura del repo

```
web/            SvelteKit: las pantallas (modo online y modo local)
platform/       api FastAPI: usuarios, puntos, ranking, juez
engine/         motor de labs: escenarios, defensas, proveedores (Azure OpenAI, Ollama)
labs/           definición de cada lab (hoy en scenarios/)
deploy/azure/   Bicep + GitHub Actions con OIDC
deploy/local/   compose.yaml y servicios falsos
docs/
```

## Decisiones abiertas

1. **Región:** apps en West Europe y Azure OpenAI en Sweden Central, o todo en zona de datos UE.
2. **Modelo:** confirmar el "mini" vigente al desplegar. Un modelo más débil hace los retos más fáciles; puede variar por lab.
3. **Suscripción y tenant de Azure** donde vive.
4. **Dominio** de la plataforma.
