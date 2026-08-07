# macOS Hello World POC

Minimal macOS app (Apple Silicon) con auto-update via GitHub Releases, sin colectar IPs.

## Estructura

```
Sources/main.swift      — app principal (NSWindow + "Hola Mundo")
Sources/Updater.swift   — auto-updater manual sin frameworks
Resources/Info.plist    — bundle config + SUFeedURL para Sparkle
scripts/build.sh        — compila .app y genera .dmg
scripts/make-release.sh — sube a GitHub Releases + actualiza appcast.xml
```

## Construir (en un Mac)

```bash
chmod +x scripts/build.sh
./scripts/build.sh
# Genera: build/HelloWorld.app + build/HelloWorld-1.0.0.dmg
open build/HelloWorld.app   # probar local
```

## Respuestas a tus preguntas

---

### ¿GitHub Releases colecta IPs?

**Técnicamente sí** (GitHub lo logea en su infraestructura), **pero tú como developer no ves nada** — GitHub no expone logs de descarga a los repo owners. Así que para efectos prácticos: **cero visibilidad de tu parte**.

Si quieres **cero absoluto** (ni GitHub ve):
- IPFS: sube el DMG a IPFS, enlaza el CID. Distribución P2P, sin servidor central.
- Cloudflare R2 + `no_log: true` en las reglas: tú controlas los logs y los puedes apagar.

Para un POC/indie app: **GitHub Releases es suficiente** — no tienes acceso a IPs.

---

### ¿Auto-update sin colectar IPs?

**Sí, completamente factible.** Dos opciones:

#### Opción A: Sparkle (recomendado para producción)
Sparkle es el estándar de la industria (Homebrew Cask lo usa, VS Code macOS, etc.).

1. Añadir Sparkle via Swift Package Manager:
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
]
```

2. En `Info.plist` ya está configurado:
```xml
<key>SUFeedURL</key>
<string>https://raw.githubusercontent.com/YOUR_ORG/YOUR_REPO/main/appcast.xml</string>
```

3. Sparkle descarga el `appcast.xml` desde GitHub raw (tú no ves quién lo descargó), verifica la firma EdDSA, descarga el DMG, y reemplaza la app automáticamente.

**¿Sparkle hace phone-home al developer?** No. Solo hace GET a la URL que tú configures (GitHub raw). Ni telemetría, ni analytics, nada.

#### Opción B: Self-updater manual (ver Updater.swift)
El código en `Sources/Updater.swift` hace exactamente lo que describes:
1. GET `api.github.com/repos/.../releases/latest` → compara versión
2. Si hay nueva: descarga el DMG
3. `hdiutil attach` → monta el DMG
4. `cp -R` → reemplaza `/Applications/HelloWorld.app`
5. `hdiutil detach` → desmonta
6. `open /Applications/HelloWorld.app` + termina la app actual

**¿Se puede auto-instalar sin pedir permiso al usuario?**

Depende del sandbox:

| | App Sandbox | Sin sandbox |
|---|---|---|
| Escribir en /Applications | ❌ bloqueado | ✅ funciona |
| Sparkle auto-update | ✅ (usa XPC helper) | ✅ |
| Self-updater manual | ❌ | ✅ |
| Notarización requerida | Sí | Sí (para distribución) |

**Para un POC sin App Store**: no uses sandbox → el auto-update funciona directo.

**Para distribución seria**: usa Sparkle 2.x — tiene un XPC helper (`Sparkle2`) que corre fuera del sandbox para hacer la instalación.

---

### Flujo completo de distribución

```
1. Desarrollas nueva versión → ./scripts/build.sh → DMG
2. ./scripts/make-release.sh 1.0.1 →
       - Sube DMG a GitHub Releases
       - Genera appcast.xml con firma EdDSA
       - Commit + push appcast.xml al repo
3. Usuarios con la app instalada:
       - App hace GET a raw.githubusercontent.com/appcast.xml
       - Compara versión → hay nueva
       - Descarga DMG desde github.com/releases/...
       - Instala y reinicia automáticamente
```

**TÚ no ves nada** — ni quién chequeó updates, ni quién descargó. GitHub ve las IPs en sus logs pero no te las expone.

---

### Para notarizar (distribución real, no POC)

Necesitas Apple Developer account ($99/año):

```bash
# 1. Firmar con Developer ID
codesign --deep --force \
    --sign "Developer ID Application: Tu Nombre (XXXXXXXXXX)" \
    --entitlements entitlements.plist \
    build/HelloWorld.app

# 2. Crear DMG y firmar el DMG también
# (ver scripts/build.sh con la firma real)

# 3. Notarizar
xcrun notarytool submit build/HelloWorld-1.0.1.dmg \
    --apple-id "tu@email.com" \
    --team-id "XXXXXXXXXX" \
    --password "@keychain:AC_PASSWORD" \
    --wait

# 4. Staple
xcrun stapler staple build/HelloWorld-1.0.1.dmg
```

Sin notarizar, macOS Gatekeeper muestra warning pero el usuario puede abrirlo con click derecho → Abrir. Para POC está bien.
