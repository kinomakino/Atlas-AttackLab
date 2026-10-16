# Decisiones del proyecto

Fecha: 2026-10-16. Estado: fase de diseño.

## Qué es

Una plataforma para aprender y practicar las técnicas de [MITRE ATLAS](https://atlas.mitre.org) atacando sistemas de IA vulnerables, con puntos y rankings. Dos piezas:

| | Plataforma online | Lab local |
|---|---|---|
| Para qué | Competir: puntos, ranking, perfil, eventos | Aprender a fondo y practicar sin límites |
| Dónde corre | Azure | En el equipo del alumno, con Docker |
| Modelo | Azure OpenAI, con cuotas por usuario | Ollama en un contenedor, sin coste |
| Labs | Solo chat al principio (prompt injection, fuga de prompt…) | Todos, también agentes, MCP y RAG |
| Puntúa | Sí | **Nunca** |

## 1. El servidor no se fía del jugador

- Lo que pasa en el equipo del jugador se puede falsificar, así que **los labs locales no dan puntos de ranking**. Sin firmas ni trucos: es una decisión de diseño, no algo pendiente de resolver.
- Solo puntúan los retos que corren en la plataforma.
- **Flag por usuario y reto**, derivada en el servidor con un secreto que solo él conoce (HMAC de usuario + reto). El objetivo vulnerable solo tiene en su contexto la flag de quien juega.
- El cliente envía la flag; **el servidor valida y suma los puntos**. Nunca se acepta "dame X puntos".

## 2. La plataforma es un objetivo desde el primer día

- **Aislamiento:** los retos atacables corren separados y no tienen acceso a la base de datos de usuarios ni a la de puntos.
- **Límites** por usuario e IP en el envío de flags y en las llamadas al modelo.
- **Registro y alertas:** tiempos de resolución imposibles, la misma flag desde varias cuentas, cuentas en cadena.
- **Login delegado** en GitHub o Microsoft. Sin contraseñas propias.
- **Reglas de juego publicadas** (qué se puede atacar y qué no) y un canal para reportar fallos de la plataforma.
- El filtro de contenido de Azure OpenAI está activo para que nadie use el chat como LLM gratis.

## 3. El lab local es seguro para quien lo descarga

- **Instalación en un comando** (`docker compose up`). Ollama va dentro y se baja los modelos solo; no hay que instalar nada a mano.
- **Imágenes firmadas** en GHCR, con lista de componentes.
- Solo escucha en `127.0.0.1`. Un lab vulnerable nunca queda expuesto a la red.
- **Contenedores sin acceso al anfitrión:** sin carpetas compartidas ni privilegios. Red interna, y salida a internet solo para bajar modelos.
- Los labs de agentes atacan **servicios falsos** dentro de esa red (ERP, correo, ficheros).
- Opcional: apuntar a un Ollama propio con GPU para ir más rápido.

## 4. Orden de trabajo

1. **Diseño de pantallas**, antes que nada más: portada con la matriz ATLAS, catálogo, página del lab (teoría, consola de ataque, qué pasa por dentro, modo vulnerable/protegido), reto resuelto, login, ranking, perfil, y descarga e instalación del lab local.
2. El backend se adapta a lo que pidan las pantallas.
3. Primera versión online: 5–6 retos de solo chat, login, puntos y ranking.
4. Después: labs de agentes, MCP y RAG en local, y eventos.

## Lo que ya hay (aparcado hasta cerrar el diseño)

- `attacklab import-atlas`: catálogo oficial de ATLAS 2026.09 en `data/atlas.json` (16 tácticas, 208 técnicas, 40 mitigaciones; Apache 2.0, © MITRE).
- Formato de lab en `scenarios/<id>/scenario.yaml` y un primer lab de ejemplo (AML.T0051.000).
- Un motor y una API de prueba en `src/attacklab/`, que se rehará según el diseño.
