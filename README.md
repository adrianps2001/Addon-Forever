# Flechazo

Addon para **World of Warcraft: Forever** (también funciona en retail/Midnight) para conocer a otros jugadores cercanos:

- Muestra a los jugadores que tienen el addon y están cerca de ti: **raza, clase, nivel, distancia, foto de frente y una breve descripción**.
- Puedes darles **like** o **pasar**.
- Si os dais like mutuamente hay **match**: desde la pestaña *Matches* puedes agregarle como **amigo**, **invitarle al grupo** o **susurrarle**.
- No distingue por género (ni real ni del personaje).
- Configurable: radio de búsqueda (100–5000 yardas), diferencia máxima de nivel y si eres visible o no.

## Instalación

Copia la carpeta `Flechazo/` (la que contiene `Flechazo.toc`) en:

| Juego | Carpeta |
|---|---|
| WoW Forever | `World of Warcraft/_forever_/Interface/AddOns/` |
| Retail (para probar) | `World of Warcraft/_retail_/Interface/AddOns/` |

Si el nombre exacto de la carpeta de Forever es distinto en tu instalación, usa la que contenga `Interface/AddOns`.

## Uso

- `/fz` o `/flechazo`: abre o cierra la ventana (también desde el botón de addons del minimapa).
- `/fz demo`: añade 4 jugadores de prueba para probar todo tú solo (2 de ellos te devuelven el like). Repite el comando para quitarlos.
- `/fz estado`: muestra si eres visible, si hay posición disponible y cuántos jugadores se han recibido.

## Cómo probarlo

1. **Solo, sin otra cuenta:** entra al juego, escribe `/fz demo` y prueba a dar like y a pasar, la pestaña *Matches* y el *Perfil*.
2. **De verdad:** hacen falta **dos personajes con el addon**, normalmente de dos personas, en el mismo continente y fuera de instancias. Esperad unos 15 segundos tras entrar y abrid `/fz`. Cada uno debería ver al otro.
3. **Foto:** cada personaje sale con su foto de frente: el retrato que trae el juego para su raza y su personaje. No se elige ni se configura, y se ve siempre, aunque el otro jugador esté lejos. Si alguna raza no tuviera retrato, se muestra el icono de su clase.
4. **Pruebas fuera del juego** (lógica y un ensayo con una API de WoW simulada; necesitas Lua 5.1):
   ```
   lua5.1 tests/run_tests.lua
   lua5.1 tests/smoke_test.lua
   ```

## Cómo funciona

- Cada personaje se une a un canal oculto por continente (`FlechazoAddon<id>`) y cada minuto envía su perfil: raza, clase, nivel, posición redondeada a 10 yardas, qué retrato de su raza le corresponde y descripción. Lo hace con `SendAddonMessageLogged`, así que si alguien escribe algo ofensivo se puede denunciar a Blizzard.
- La foto no se envía como imagen: solo viaja una letra que indica cuál de los retratos del juego mostrar, así que no hay que renderizar al personaje.
- Los likes se envían por susurro de addon solo a esa persona. Cada uno guarda sus likes, y cuando los dos coinciden aparece el match en ambos lados.
- Los datos se guardan por personaje en `FlechazoCharDB`.

## Limitaciones conocidas

- **Solo encuentra a jugadores que también tengan Flechazo.** Ningún addon puede leer la lista de todos los jugadores cercanos.
- **No funciona dentro de mazmorras, bandas, campos de batalla ni arenas:** Blizzard bloquea ahí la posición y la comunicación entre addons.
- **Las cuentas de prueba (trial) y veteranas no pueden enviar mensajes de addon** en Forever, así que no serán visibles.
- Los likes por susurro solo funcionan entre reinos iguales o conectados, y probablemente no entre facciones distintas.
- **Privacidad:** cualquiera con el addon en tu continente recibe tu posición aproximada mientras seas visible. Puedes desactivarlo en *Perfil*. Además, quien sepa leer los archivos guardados del addon podría ver quién le ha dado like antes de decidir.
- "Quitar" un match también bloquea a esa persona para que no vuelva a aparecer.
- El número de interfaz `16001` es el de la beta de Forever; si en la versión final cambia, el juego marcará el addon como "desactualizado". Puedes activarlo igualmente o actualizar el número en `Flechazo.toc` (compruébalo con `/dump select(4, GetBuildInfo())`).
