# Decisiones del proyecto

Última revisión: 2026-10-16.

## Qué es

Un **lab local** para aprender y practicar las técnicas de [MITRE ATLAS](https://atlas.mitre.org) atacando sistemas de IA vulnerables. Cada alumno lo instala en su equipo y lo usa sin coste para nosotros: el modelo, los agentes y los servicios falsos corren en su máquina.

## 1. Todo local

- El alumno pone el equipo. Nosotros no pagamos infraestructura ni modelos.
- Modelo en local con Ollama, dentro del propio lab.
- Todos los labs funcionan en local, también los de agentes, MCP y RAG.

## 2. Sin ranking: progreso personal

- En una máquina que controla el alumno ninguna puntuación es fiable, así que **no hay ranking ni puntos competitivos**.
- Hay progreso personal: labs resueltos, modo protegido superado, matriz completada y medallas. Se guarda en su equipo.
- Hacer trampas aquí no tiene sentido: solo se engaña uno mismo.

## 3. El lab es seguro para quien lo instala

- **Instalación en un comando** (`docker compose up`). Ollama va dentro y se baja los modelos solo.
- **Imágenes firmadas** en GHCR, con lista de componentes.
- Solo escucha en `127.0.0.1`. Un lab vulnerable nunca queda expuesto a la red.
- **Contenedores sin acceso al anfitrión:** sin carpetas compartidas ni privilegios, usuario no root.
- **Red interna** para labs y servicios falsos, sin salida a internet. Solo Ollama sale, para bajar modelos.
- Los labs de agentes atacan **servicios falsos** dentro de esa red (ERP, correo, ficheros).
- Opcional: apuntar a un Ollama propio con GPU para ir más rápido.

## 4. Para más adelante (no ahora)

- **Modo aula o evento:** el organizador monta el lab en su servidor y los alumnos lo atacan por la red. Ahí sí se podría puntuar de forma segura, con ranking por evento.
- **Versión online de pago**, alojada por nosotros.

Descartado por ahora: plataforma online en Azure, login, ranking global y verificación de entregas en servidor.

## 5. Orden de trabajo

1. ✅ Diseño de pantallas (lienzo privado: https://claude.ai/artifact/SWFEnTmrcW3kPgGBSbv2b3). Hay que adaptarlo al modo local: sobran login y ranking, y el perfil pasa a ser "tu progreso".
2. Motor de labs + primeros labs + `compose.yaml` funcionando con un comando.
3. La web del lab sobre ese motor, con el diseño aprobado.
4. Ampliar labs: agentes, MCP, RAG.

## Lo que ya hay

- `attacklab import-atlas`: catálogo oficial de ATLAS 2026.09 en `data/atlas.json` (16 tácticas, 208 técnicas, 40 mitigaciones; Apache 2.0, © MITRE).
- Formato de lab en `scenarios/<id>/scenario.yaml` y un primer lab de ejemplo (AML.T0051.000).
- Un motor y una API de prueba en `src/attacklab/`.
