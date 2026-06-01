# Neural ONE — Onboarding

Instalador de un solo comando para dejar una laptop **macOS** lista para trabajar
con el ecosistema de data del equipo.

## Instalación

Abre **Terminal** y pega:

```bash
curl -fsSL https://raw.githubusercontent.com/NeuralONE/neural-one-installer/main/install.sh | bash
```

El instalador te irá guiando. Te pedirá confirmación antes de instalar cada
herramienta y abrirá los flujos de login de Google Cloud y GitHub en el navegador.

## Qué hace

1. **Prerequisitos** — instala (con tu confirmación, vía [Homebrew](https://brew.sh))
   lo que haga falta: `git`, `gh`, `gcloud`, `jq`, `yq`, `python3`, VS Code y Claude Code.
2. **Autenticación** — Google Cloud + GitHub.
3. **Autorización** — comprueba que tu cuenta está dada de alta en el equipo.
4. **Configuración** — clona el repo de configuración privado y ejecuta el
   bootstrap del equipo (settings, hooks, MCP, skills, memoria) y un healthcheck.

Al terminar, abre el workspace en VS Code y escribe `claude` en la terminal
integrada para tu primera sesión.

## ¿Es seguro ejecutar esto?

Sí, y puedes comprobarlo tú mismo: este `install.sh` está a la vista en este repo
público y **no contiene nada sensible** — solo orquesta la instalación. Toda la
configuración del equipo vive en un repo **privado**, al que solo se accede
después de que te autentiques con tu cuenta. Léete el script antes de ejecutarlo
si quieres.

## Requisitos previos

- macOS (Apple Silicon o Intel).
- Tu cuenta `@neural.one` dada de alta en el equipo (lo gestiona el administrador
  del equipo). Si no lo está, el instalador te lo dirá y se detendrá.
