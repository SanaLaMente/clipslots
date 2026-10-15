# ClipSlots

Diez portapapeles numerados para macOS. Un solo archivo de Swift, sin dependencias.

| Atajo | Qué hace |
| --- | --- |
| **⌘C + N** | Con ⌘ y C apretados, tocás un número (1–9, 0): guarda lo copiado en el slot N. |
| **⌘V + N** | Con ⌘ y V apretados, tocás un número: pega el slot N. Tu portapapeles queda como estaba. |

⌘C y ⌘V solos siguen funcionando igual que siempre.

## Instalar

```bash
curl -fsSL https://raw.githubusercontent.com/SanaLaMente/clipslots/main/install.sh | bash
```

Requisitos: macOS 11 o superior y las Command Line Tools de Xcode
(`xcode-select --install`). El instalador compila la app en tu Mac, la pone en
`/Applications` (o `~/Applications`) y la deja arrancando al iniciar sesión.

Después activá **ClipSlots** en *Ajustes del Sistema → Privacidad y seguridad →
Accesibilidad*. Sin ese permiso macOS no deja leer el teclado.

Para actualizar, corré el mismo comando.

## Desinstalar

```bash
curl -fsSL https://raw.githubusercontent.com/SanaLaMente/clipslots/main/uninstall.sh | bash
# y para borrar también los slots guardados:
curl -fsSL https://raw.githubusercontent.com/SanaLaMente/clipslots/main/uninstall.sh | bash -s -- --purge
```

## Dónde se guardan los slots

En `~/Library/Application Support/ClipSlots/slots.json`, un JSON plano con
permisos `600` (solo tu usuario lo lee). **No está encriptado**: si copiás algo
sensible a un slot, queda en ese archivo. Lo que los gestores de contraseñas
marcan como oculto (`org.nspasteboard.ConcealedType`) nunca se guarda.

## Cómo funciona

Un `CGEventTap` escucha el teclado de todo el sistema:

- **⌘C** pasa directo a la app. Si mientras C sigue apretada llega un número,
  ClipSlots se traga ese número, espera a que la app termine de copiar y guarda
  el texto.
- **⌘V** se retiene. Si llega un número, ClipSlots pone ese slot en el
  portapapeles, simula ⌘V y a los 400 ms devuelve lo que había. Si soltás la V
  sin número, reenvía el ⌘V normal.

## Limitaciones

- Solo texto plano (no imágenes ni texto con formato).
- El ⌘V normal pega al **soltar** la V, no al apretarla, y mantener ⌘V apretado
  no repite el pegado.
- Cada instalación se firma ad-hoc, así que al actualizar macOS vuelve a pedir
  el permiso de Accesibilidad.
- En campos de contraseña macOS activa *Secure Input* y bloquea los atajos.
