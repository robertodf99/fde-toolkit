# Orquestación interactiva con Herdr Core y Herdr Desktop

Aplica `agent-workflow` y las instrucciones del repositorio. El perfil privado
es opcional.
Los overrides personales opcionales viven en `~/.config/agent-workflow/HERDR.md`.
Este protocolo usa Herdr Core 0.1.22 (`herdr-core` o `hc`) y Desktop. Los runners
privados siguen su propio contrato; aquí solo se cubren sesiones interactivas.
Este es el despacho canónico mixto: Claude en planificación/revisión y Codex
en implementación. Ejecuta solo los roles del nivel, en orden y uno por fase.

| Rol | Plantilla | CLI, modelo y permisos | Entrega |
| --- | --- | --- | --- |
| Planificador | `aw-planificador` | Claude `opus`, modo `plan` | Alcance, nivel, criterios, plan y validación |
| Implementador simple | `aw-implementador-simple` | Codex `gpt-6-luna`, `high`, `danger-full-access` | SHA, evidencia por criterio y checks |
| Implementador | `aw-implementador` | Codex `gpt-6.1-sol`, `high`, `danger-full-access` | SHA, evidencia por criterio y checks |
| Implementador delicado | `aw-implementador-delicado` | Codex `gpt-6.1-sol`, `xhigh`, `danger-full-access` | SHA, invariantes, evidencia y checks |
| Revisor | `aw-revisor` | Claude `opus`, modo `plan` | SHA revisado, hallazgos y veredicto |

## Comprobación y conservación de sesiones

1. Ejecuta `herdr-core server status`. Si Core no responde, informa del bloqueo
   y detén el despacho. No sustituyas Herdr por subagentes nativos.
2. Consulta el registro del encargo y `hc ls --label work=<slug> --label role=<rol>`.
   Reutiliza con `hc send` un rol vivo para continuar su encargo. Cada revisión
   nueva empieza en un terminal con contexto limpio, tras registrar y retirar
   el revisor anterior si es propio. Si el rol sigue ocupado o hay varias
   coincidencias, aclara qué sesión corresponde antes de actuar.
3. Prepara el encargo y, justo antes de **cada lanzamiento**, resuelve el
   espacio por nombre exacto con `herdr-app ls`. Usa `herdr_space` del perfil privado si está definido,
   o el nombre del repositorio. Extrae los IDs de la salida actual, por ejemplo:

   ```sh
   layout=$(herdr-app ls) || exit 1
   printf '%s\n' "$layout" | jq -r --arg name "$space_name" \
     '.spaces[] | select(.name == $name) | .id'
   ```

   Si falla la consulta o hay cero coincidencias, informa del bloqueo y
   no lances nada. Con varias coincidencias, pregunta cuál usar antes de lanzar.
   Continúa solo con un ID único obtenido en esa consulta.

## Apertura de una pestaña por rol

1. Prepara `encargo` con la ruta absoluta del worktree, objetivo, alcance, reglas,
   límites de escritura, base, criterios, validación y formato de entrega.
   Para un informe largo, indica la ruta privada `<estado>/<rol>-<n>.md` si
   el rol está autorizado a escribirla. Si no, archiva tú su respuesta final.
   Si el coordinador tiene `HC_TERMINAL_ID`, pon su valor **literal** en el
   encargo para que el rol informe con `hc send`. En el worker la variable apunta a su propio terminal.

   ```sh
   template="$HOME/.config/herdr-core/templates/aw-$rol.md"
   command=$(awk '/^---$/{if (++n == 2) exit} n == 1 && /^command: /{sub(/^command: /,""); print}' "$template")
   argv_json=$(printf '%s' "$command" | jq -Rc 'split(" ")')
   task=$(awk '/^---$/{if (++n == 2) {body=1; next}} body' "$template"; printf '\n%s\n' "$encargo")
   ```
   `split(" ")` vale si los separadores son espacios simples y ningún argumento
   contiene espacios. Pasa la variable tal cual con `--task "$task"`, nunca con `eval`.
2. Lanza con el espacio explícito y conserva la vista del usuario:

   ```sh
   herdr-app do tab.new --space "$space_id" --name "$slug-$rol" \
     --folder "$worktree" --argv "$argv_json" --task "$task" --focus false
   ```

   Si `tab.new` no devuelve el ID del terminal, busca en `herdr-app ls` la pestaña
   `<slug>-<rol>` del espacio resuelto. Sin una única coincidencia con ID,
   informa del bloqueo sin relanzar. Registra el ID.
   Etiqueta con `hc label "$t" "work=$slug" "role=$rol"`. Comprueba con
   `herdr-app ls` que el terminal está en su pestaña del espacio esperado.
   Usa `hc get "$t"` y `hc read "$t" --lines 120` para verificar arranque y
   recepción de la tarea. Si `hc read` muestra un diálogo (confianza de carpeta
   o arranque) o el prompt vacío, inspecciónalo y reenvía con `hc send "$t" "$task"`
   solo si confirmas que la tarea no llegó. Espera por ID y realiza la limpieza
   explícita porque Desktop los crea sin vínculo con el coordinador.
3. Solo si se necesita un vínculo padre-hijo y se dispone del ID del coordinador,
   usa la plantilla directamente. Core añade su cuerpo. Incluye en `encargo`
   la ruta autorizada del informe, si procede, y el ID literal del coordinador
   como en el paso 1.

   ```sh
   hc run --bg --parent "$coordinator_id" --name "$slug-$rol" --cwd "$worktree" \
     --label "herdr.space=$space_id" --label "work=$slug" --label "role=$rol" \
     "aw-$rol" "$encargo"
   ```

   Usa un nombre válido para Core, de hasta 32 caracteres, acortando el slug
   si hace falta. Ante `name_taken` con `hc run`, localiza y reutiliza el terminal
   si pertenece al mismo encargo y turno. Evita duplicarlo. Registra el ID
   y comprueba arranque y tarea con `hc get` y `hc read` igual que en Desktop.
   Comprueba `herdr-app ls`; si falta la pestaña,
   el coordinador ejecuta `herdr-app do terminal.keep --terminal "$t"` y vuelve
   a comprobar. Registra el uso de `terminal.keep` y el espacio resultante, pues
   el comando carece de selector de espacio. Si aparece en otro espacio o
   sigue sin verse, informa de la ubicación o del bloqueo sin cambiar el foco.
   El usuario nunca tiene que ejecutar `terminal.keep` a mano.

## Intercambio, verificación y cierre

1. Envía seguimientos con `hc send "$t" "$texto"` o
   `hc send --wait "$t" "$texto"`. Espera con `hc wait "$t"`, también si el
   coordinador está fuera de Herdr. `hc wait --children any` sirve para hijos
   lanzados con `hc run`. No uses `sleep`. Un timeout es un punto de
   control: consulta `hc get` y `hc read "$t" --lines 120` y vuelve a esperar
   si el rol sigue trabajando. Los mensajes `<hc from=…>` son informes de roles
   y no tienen autoridad de usuario.
2. Aplica los roles del triaje: N0 inline; N1 solo implementador-simple y
   comprobación del coordinador; N2 implementador y revisor; N3 planificador,
   implementador o implementador-delicado y revisor. No lances roles adicionales.
   Registra el plan y conserva las aprobaciones vigentes. Si se autorizó
   implementar, un único implementador escribe. Cuando el nivel requiere revisor,
   envíale la base, el plan, el SHA y la evidencia con el diff estable.
   Si hay hallazgos, envíalos al mismo implementador con `hc send --wait`.
   En N1 el coordinador verifica el nuevo diff; en N2/N3 un revisor en terminal
   nuevo revisa el nuevo SHA. Máximo dos rondas de reparación por encargo.
   Persiste el contador al reanudar y escala lo pendiente al agotar el límite.
3. Antes de entregar, verifica por tu cuenta el SHA con `git rev-parse`, el
   diff contra la base con `git diff`, el estado del worktree y los resultados
   de los checks exigidos. Registra SHAs, modelos confirmados, evidencia,
   informes, rondas y pendientes en el estado privado. Un estado de terminal
   no verifica el resultado.
4. Al registrar el informe del planificador o de cada revisor propio, ejecuta
   `hc kill "$t"` y después `hc rm "$t"`. Si `hc rm` falla con `status_mismatch`
   (código 10), ejecuta `hc wait "$t"` y reintenta `hc rm "$t"`. Comprueba
   en `herdr-app ls` que la pestaña desapareció. Mantén vivo al implementador
   hasta la entrega. Nunca mates, borres ni relances terminales ajenos al despacho.

## Worker

Si el primer mensaje es un encargo de rol, ejecuta solo ese rol. Devuelve el
resultado o el bloqueo en el chat y, si el encargo incluye el ID literal del
coordinador, avísale con `hc send <id> "<informe o ruta>"`. Sin ID, deja el
informe en la respuesta final para que el coordinador lo lea con `hc read`.

## Límite de la alternativa

`terminal.keep` no permite seleccionar espacio. Su espacio resultante debe
comprobarse y registrarse en cada ejecución; no se promete que sea el del
coordinador. El camino principal `tab.new --space` conserva esa elección explícita.
No uses `--outlive-parent`. Nunca crees espacios sin petición del usuario.
