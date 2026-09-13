# Window Switcher

Plugin de [Omarchy](https://omarchy.org/) para el shell (Quickshell) que lista
**todas las ventanas abiertas en cualquier workspace** y te permite saltar
directamente a la que elijas, con una **vista previa** de la ventana
seleccionada en el panel derecho.

```
┌──────────────────────────────────────────────────────────────┐
│ Buscar ventanas...                              12 ventanas   │
├───────────────────────────┬──────────────────────────────────┤
│ 1                         │  [icono] Google Chrome   [⛶] [×]  │
│  [icono] Google Chrome    │  Bandeja de entrada - Correo      │
│          Bandeja de entra │  [⏮] [⏸] [⏭]  Artista — Canción  │
│  [icono] Alacritty        │  ┌────────────────────────────┐  │
│          ~/proyectos · nv │  │                            │  │
│ 2                         │  │      vista previa          │  │
│  [icono] Spotify          │  │                            │  │
│          Artista — Canción│  └────────────────────────────┘  │
└───────────────────────────┴──────────────────────────────────┘
```

## Características

- **Todas las ventanas, todos los workspaces**, agrupadas por número de
  workspace y ordenadas espacialmente. Scroll automático hasta la ventana
  seleccionada al navegar.
- **Icono + aplicación + actividad**: icono de la app (resuelto vía desktop
  entries), nombre de la aplicación y actividad (título con el sufijo del
  navegador limpio, p. ej. `Inbox — Google Chrome` → `Inbox`).
- **Actividad enriquecida de terminales**: directorio actual y comando en primer
  plano (`~/proyectos/omarchy · nvim`), sin destellos al abrir.
- **Vista previa** de la ventana seleccionada, incluso en otro workspace. Por
  defecto en modo **still** (un frame, sin parpadeo); también `live` u `off`.
- **Mensaje claro** si una ventana no se puede previsualizar (permiso o
  superficie protegida); el fondo del panel es opaco, no transparenta el
  escritorio.
- **Salto automático**: al enfocar una ventana en otro workspace, Hyprland
  cambia a ese workspace.
- **Búsqueda escribiendo** y **navegación por zonas** con teclado.
- **Controles icon-only**: pantalla completa (que además enfoca la ventana) y
  cerrar junto a los detalles; anterior / pausa-reproducir / siguiente para
  multimedia.
- **Altura fija** del panel derecho: cambiar de ventana no produce saltos.
- **Tema**: hereda la paleta de Omarchy (`Color.menu.*`, `Style.*`).

## Instalación

### Desarrollo local (enlace simbólico)

```bash
ln -sfn /home/diego/Projects/repos/omarchy/plugins/window-switcher \
        ~/.config/omarchy/plugins/diego.window-switcher
omarchy-shell shell rescanPlugins
omarchy plugin enable diego.window-switcher
```

### Desde git

```bash
omarchy plugin add <url-del-repo> --enable
```

## Atajo de teclado

Añade esto a `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "Window switcher",
  "omarchy-shell shell toggle diego.window-switcher")
```

> Si `SUPER + D` ya estaba asignado a otro plugin, primero libera la tecla:
> `hl.unbind("SUPER + D")`.

## Uso

| Entrada | Acción |
|---|---|
| `↑` / `↓` | Navegar entre ventanas |
| `Page Up` / `Page Down` | Navegar por páginas |
| `Home` / `End` | Primera / última ventana |
| `→` / `Tab` | Pasar al panel de controles |
| `←` / `→` (en controles) | Recorrer los controles |
| `←` (al inicio) / `Esc` | Volver a la lista |
| `Enter` | Enfocar la ventana / activar el control |
| `Espacio` | Pausar/reproducir si la ventana tiene multimedia |
| Escribir | Filtrar por aplicación y título |
| `Backspace` | Borrar el último carácter |
| `Ctrl+U` | Limpiar el filtro |
| `Esc` | Limpiar el filtro; si está vacío, cerrar |
| Clic izquierdo | Enfocar la ventana |
| Clic medio | Cerrar la ventana |
| Pasar el ratón | Seleccionar la ventana |
| Clic fuera | Cerrar el overlay |

## Configuración (`settings.json`)

Opcional. Copia `settings.example.json` a `settings.json` junto al plugin:

```bash
cp ~/.config/omarchy/plugins/diego.window-switcher/settings.example.json \
   ~/.config/omarchy/plugins/diego.window-switcher/settings.json
```

Se relee en cada apertura del overlay.

| Clave | Valores | Significado |
|---|---|---|
| `preview` | `"still"` (def.), `"live"`, `"off"` | un frame por selección, captura continua, o sin vista previa |
| `groupByWorkspace` | `true` (def.) / `false` | agrupar por workspace |
| `rowDensity` | `"comfortable"` (def.), `"compact"` | altura de fila/icono |
| `sort` | `"workspace"` (def.), `"recency"`, `"app"` | orden dentro de los grupos |
| `terminalActivity` | `true` (def.) / `false` | enriquecer terminales con cwd + comando |

## Detalles técnicos

- Recolecta las ventanas recorriendo `Hyprland.workspaces.values` y, de cada
  workspace, `ws.toplevels.values`; omite los workspaces especiales (`id <= 0`).
- La ventana activa se detecta con `focusHistoryID === 0` (Hyprland ya no envía
  `focus` en `clients`).
- Enfoca con `hyprctl dispatch 'hl.dsp.focus({ window = "address:0x…" })'`,
  **antes** de ocultar el overlay (con `keepLoaded: false` la instancia se
  destruye al ocultarse y cualquier llamada posterior fallaría).
- Resuelve nombres e iconos con `DesktopEntries.applications` y
  `Quickshell.iconPath()`; si no hay coincidencia, deriva un nombre legible del
  `appId`.
- La vista previa usa una única `ScreencopyView` (`captureSource` del toplevel
  Wayland), con fondo opaco, y solo se muestra cuando `hasContent` está listo.
- La actividad de terminal la calcula `window-scan.sh` con
  `hyprctl -j clients` + `/proc` (proceso hijo, `cwd` y grupo de proceso en
  primer plano). El overlay espera acotadamente a ese escaneo para no mostrar
  primero el título y luego el texto enriquecido.
- Multimedia vía `Quickshell.Services.Mpris` y audio vía
  `Quickshell.Services.Pipewire`.

## Requisitos

- Omarchy con Hyprland.
- Quickshell (incluido con Omarchy).
- `jq` y `pgrep` para la actividad de terminal (presentes en Omarchy).

## Licencia

MIT — ver [LICENSE](LICENSE).
