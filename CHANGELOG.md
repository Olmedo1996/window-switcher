# Changelog

Todas las novedades relevantes de este plugin se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/).

## [1.1.1] - 2026-09-12

### Corregido

- Enfocar una ventana ya no falla con `TypeError: hyprDispatch is not a
  function`: el foco se despacha antes de ocultar el overlay (con
  `keepLoaded: false` la instancia se destruye al ocultarse).
- Detección de la ventana activa: Hyprland ya no envía `focus` en `clients`;
  ahora se usa `focusHistoryID === 0`.
- Las ventanas sin permiso de captura ya no transparentan el fondo: la vista
  previa tiene fondo opaco y la superficie de captura se oculta sin contenido.
- Las terminales ya no muestran un destello del título antes del `cwd`/comando:
  el overlay espera (acotado) a que termine el escaneo antes de mostrarse.
- El panel derecho mantiene altura fija, así que cambiar de ventana no produjo
  saltos de layout por textos largos.

### Cambiado

- Eliminado el botón "Fijar" y el agrupado de favoritos.
- El botón de pantalla completa y el de cerrar ahora son iconos junto a los
  detalles de la ventana; "Pantalla completa" también enfoca la ventana.
- Controles de música solo con iconos: anterior, pausa/reproducir y siguiente.
- Los iconos de app del panel derecho se resuelven igual que en la lista.
- Los encabezados de sección muestran solo el número del workspace.

## [1.1.0] - 2026-09-12

### Añadido

- `settings.json` opcional con `preview` (`still`/`live`/`off`),
  `groupByWorkspace`, `rowDensity`, `sort`, `terminalActivity` y `pinFirst`
  (ver `settings.example.json`).
- Actividad enriquecida de terminales: directorio actual y comando en primer
  plano, obtenidos con `window-scan.sh` (`hyprctl` + `/proc`), activada por
  defecto.
- Favoritos: `Ctrl+P` fija/desfija por aplicación, persistidos en
  `~/.local/state/omarchy/window-switcher-pins.json` y mostrados primero.
- Navegación por zonas con el teclado: `→`/`Tab` entra al panel de controles,
  `←`/`→` recorre los controles, `Enter` los activa y `←` al inicio/`Esc` vuelve
  a la lista.
- Estado de captura con mensaje claro cuando una ventana no se puede
  previsualizar (permiso o superficie protegida).

### Cambiado

- Vista previa por defecto en modo **still** (un frame por selección) para
  eliminar el parpadeo y reducir el consumo; `live` y `off` siguen disponibles.
- La vista previa usa una sola `ScreencopyView` y solo se revela cuando
  `hasContent` está listo.
- El panel derecho se reorganiza: **detalle y controles arriba**, vista previa
  abajo, para que las ventanas de distinto tamaño no muevan los controles.
- La lista ahora **hace scroll automático** hasta la ventana seleccionada.
- Se eliminó el botón "Enfocar" (Enter ya enfoca) y el badge multimedia de cada
  fila (pasa al panel de detalle).
- Estilo general más limpio: filas compactas, encabezados sutiles y pie de una
  línea.

## [1.0.0] - 2026-09-12

### Añadido

- Versión inicial del plugin `diego.window-switcher`.
- Listado de todas las ventanas abiertas en cualquier workspace, agrupadas por
  workspace y ordenadas espacialmente.
- Icono de aplicación, nombre de la aplicación y actividad (título con el
  sufijo del navegador limpio) por cada ventana.
- Vista previa en vivo de la ventana seleccionada en el panel derecho
  (`ScreencopyView`).
- Salto automático a la ventana y su workspace al enfocar.
- Búsqueda incremental al escribir (por aplicación y título).
- Navegación con teclado (`↑`/`↓`, `Page Up`/`Page Down`, `Home`/`End`) y ratón
  (hover para seleccionar).
- Acciones de ventana: enfocar, alternar pantalla completa y cerrar.
- Insignia e integración multimedia vía MPRIS y Pipewire (reproducción/pausa e
  indicador de audio).
- Tema basado en los tokens del shell de Omarchy (`Color.menu.*`, `Style.*`).

[1.0.0]: https://example.com/window-switcher/releases/tag/v1.0.0
