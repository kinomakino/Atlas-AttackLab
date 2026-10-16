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

## 4. Herramienta abierta, retos como módulos

- **La herramienta es gratis y de código abierto** en GitHub: portal, motor, matriz y `compose.yaml`.
- **Cada reto es un módulo** versionado y firmado: su definición y, si los necesita, sus servicios falsos. Se publica en un registro de contenedores (OCI).
- **Un catálogo firmado** dice qué retos existen. La matriz lo lee y pinta todas las casillas; al pinchar, se abre el reto o se ofrece instalarlo.
- Publicar un reto nuevo es subir un módulo. La herramienta no cambia.
- **Modelo de negocio:** unos 30 retos gratis (1–2 por táctica) y suscripción para el resto y los nuevos de cada mes. Los de pago salen en la matriz con candado.

## 5. Protección de los retos de pago

Objetivo: no impedir la piratería al 100 % (imposible en local), sino que no sea fácil ni gratis, y que quien filtre quede identificado. La protección va en los retos, no en la herramienta, porque la herramienta es abierta.

- **Cifrado:** el módulo de pago viaja cifrado. La clave la da el servidor de licencias al arrancar el reto, por dispositivo y de corta duración, y se descifra en memoria. Sin licencia, no se juega.
- **Licencia:** comprobación al arrancar, con margen sin conexión (unos 7 días), límite de dispositivos y alertas de uso anómalo. Los retos gratis no necesitan conexión.
- **Marca de agua por comprador:** cada descarga lleva datos únicos de esa cuenta (empresas ficticias, datos falsos, cadenas en documentos). Un pack filtrado se rastrea hasta su cuenta.
- **Contenido nuevo cada mes:** lo pirateado envejece.
- Se cobra con una plataforma de pagos que gestione el IVA europeo (Stripe, Paddle, Lemon Squeezy, o Thinkific si ya se usa).

**Ahora:** el formato de módulo deja sitio para firma, cifrado y marca de agua. El servidor de licencias se monta con el primer reto de pago.

## 6. Para más adelante (no ahora)

- **Modo aula o evento:** el organizador monta el lab en su servidor y los alumnos lo atacan por la red. Ahí sí se podría puntuar de forma segura, con ranking por evento.
- **Versión online de pago**, alojada por nosotros.

Descartado por ahora: plataforma online en Azure, login, ranking global y verificación de entregas en servidor.

## 7. Orden de trabajo

1. ✅ Diseño de pantallas (lienzo privado: https://claude.ai/artifact/SWFEnTmrcW3kPgGBSbv2b3). Hay que adaptarlo al modo local: sobran login y ranking, y el perfil pasa a ser "tu progreso".
2. **Primer reto completo, ya como módulo** (AML.T0051.000, "Saca el secreto del asistente"): motor, pantalla del lab y de reto resuelto con el diseño aprobado, **matriz ATLAS clicable** leyendo el catálogo, y `docker compose up` probado.
3. Más retos gratis.
4. Servidor de licencias y primeros retos de pago.
5. Labs de agentes, MCP y RAG.

## Lo que ya hay

- `attacklab import-atlas`: catálogo oficial de ATLAS 2026.09 en `data/atlas.json` (16 tácticas, 208 técnicas, 40 mitigaciones; Apache 2.0, © MITRE).
- Formato de lab en `scenarios/<id>/scenario.yaml` y un primer lab de ejemplo (AML.T0051.000).
- Un motor y una API de prueba en `src/attacklab/`.
