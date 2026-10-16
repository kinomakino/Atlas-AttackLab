# Arquitectura

Última revisión: 2026-10-16. Todo local; ver [decisiones.md](decisiones.md).

## Qué instala el alumno

```
compose.yaml  ── todo escucha en 127.0.0.1:8080
├── portal      la web del lab (catálogo, labs, tu progreso)
├── runner      el motor de labs: monta el reto, llama al modelo,
│               aplica las defensas y hace de juez
├── ollama      el modelo; se baja la primera vez
└── servicios falsos por lab (ERP, correo, MCP, RAG…), con perfiles
    para arrancar solo los del lab que se juega
```

- **Un solo comando:** `docker compose up`. No hay que instalar Python, Ollama ni nada más.
- **Progreso** en un volumen de Docker del alumno. Sin cuentas ni login.
- **GPU opcional:** la variable `OLLAMA_URL` apunta a un Ollama propio si se quiere más velocidad.

## Seguridad del lab

| Medida | Para qué |
|---|---|
| Puertos publicados solo en `127.0.0.1` | Nadie de la red llega a los labs vulnerables |
| Red interna sin salida a internet para labs y servicios falsos | Un ataque no puede salir del lab |
| Solo `ollama` con salida, en su propia red | Para descargar modelos |
| Sin carpetas del anfitrión, sin privilegios, usuario no root, `cap_drop: ALL`, solo lectura donde se pueda | Romper un lab no da acceso al equipo |
| Imágenes en GHCR firmadas con cosign desde GitHub Actions, con SBOM | El alumno comprueba que ejecuta lo publicado |
| Versiones fijas de imágenes y modelos | Todos tienen el mismo lab |

## Motor de labs

Cada lab es una carpeta con su definición (`scenario.yaml`) y, si los necesita, sus servicios falsos. El motor:

1. Monta el contexto del objetivo (instrucciones, documentos, herramientas) en modo **vulnerable** o **protegido**.
2. Llama al modelo.
3. Aplica las defensas del modo protegido.
4. Hace de **juez**: comprueba si se cumplió el objetivo (la flag salió, se invocó la herramienta prohibida, se envió el correo…).
5. Devuelve la respuesta y la **traza** paso a paso, que es lo que el portal enseña en "Qué pasa por dentro".

## Estructura del repo

```
web/            la web del lab (diseño aprobado)
engine/         motor de labs y proveedor Ollama
labs/           definición de cada lab (hoy en scenarios/)
deploy/         compose.yaml, servicios falsos, CI de imágenes firmadas
docs/
```

## Aparcado

La plataforma online en Azure (login, ranking, verificación en servidor) queda fuera hasta que se retome el modo aula/evento o la versión de pago. Decisiones que ya estaban tomadas para entonces: West Europe, gpt-4.1-mini como modelo por defecto y suscripción "LA BUENA 2025".
