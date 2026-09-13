# Window Switcher

Plugin de [Omarchy](https://omarchy.org/) para el shell (Quickshell) que lista
**todas las ventanas abiertas en cualquier workspace** y te permite saltar
directamente a la que elijas, con una **vista previa en vivo** de la ventana
seleccionada en el panel derecho.

```
┌──────────────────────────────────────────────────────────────┐
│ Buscar ventanas...                              12 ventanas   │
├───────────────────────────┬──────────────────────────────────┤
│ Workspace 1               │  ┌────────────────────────────┐  │
│  [icono] Google Chrome    │  │                            │  │
│          Bandeja de entra │  │   vista previa en vivo     │  │
│  [icono] Terminal         │  │   de la ventana elegida    │  │
│          ~/proyectos      │  └────────────────────────────┘  │
│ Workspace 3               │  [icono] Google Chrome            │
│  [icono] Spotify          │  Bandeja de entrada - Correo      │
│     Artista — Canción  ⏸  │  Workspace 1                     │
│                           │  [Enfocar] [Pausar] [⛶] [×]      │
└───────────────────────────┴──────────────────────────────────┘
```

## Características

- **Todas las ventanas, todos los workspaces**, agrupadas por workspace
  (`Workspace N`) y ordenadas espacialmente.
- **Icono + aplicación + actividad**: por cada ventana se muestra el icono de
  la app (resuelto vía desktop entries), el nombre de la aplicación y la
  actividad (título de la ventana con el sufijo del navegador limpio, p. ej.
  `Inbox — Google Chrome` → `Inbox`).
- **Vista previa en vivo** de la ventana seleccionada (`ScreencopyView`), incluso
  si está en otro workspace.
- **Salto automático**: al enfocar una ventana en otro workspace, Hyprland
  cambia a ese workspace.
- **Búsqueda escribiendo**: filtra por aplicación y título al instante.
- **Navegación con teclado y ratón**.
- **Acciones**: enfocar, pantalla completa y cerrar (clic medio sobre la fila o
  botón `×` en el panel de vista previa).
- **Insignia de multimedia/audio**: muestra reproducción/pausa para reproductores
  MPRIS y un indicador de sonido para ventanas que emiten audio.
- **Tema**: hereda la paleta de Omarchy (`Color.menu.*`, `Style.*`), por lo que
  se adapta a cada tema.

## Instalación

### Desarrollo local (enlace simbólico)

```bash
ln -sfn /home/diego/Projects/repos/omarchy/plugins/window-switcher \
        ~/.config/omarchy/plugins/window-switcher
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
| `Enter` | Enfocar la ventana seleccionada |
| Escribir | Filtrar por aplicación y título |
| `Backspace` | Borrar el último carácter |
| `Ctrl+U` | Limpiar el filtro |
| `Esc` | Limpiar el filtro; si está vacío, cerrar |
| Clic izquierdo | Enfocar la ventana |
| Clic medio | Cerrar la ventana |
| Pasar el ratón | Seleccionar la ventana |
| Clic fuera | Cerrar el overlay |

## Detalles técnicos

- Recolecta las ventanas recorriendo `Hyprland.workspaces.values` y, de cada
  workspace, `ws.toplevels.values`; omite los workspaces especiales (`id <= 0`).
- Enfoca con `hyprctl dispatch 'hl.dsp.focus({ window = "address:0x…" })'`.
- Resuelve nombres e iconos con `DesktopEntries.applications` y
  `Quickshell.iconPath()`; si no hay coincidencia, deriva un nombre legible del
  `appId`.
- La vista previa usa `ScreencopyView` con `captureSource` del toplevel Wayland.
- Multimedia vía `Quickshell.Services.Mpris` y audio vía
  `Quickshell.Services.Pipewire`.

## Requisitos

- Omarchy con Hyprland.
- Quickshell (incluido con Omarchy).

## Licencia

MIT — ver [LICENSE](LICENSE).
