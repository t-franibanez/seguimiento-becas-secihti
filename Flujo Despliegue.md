# Arquitectura de Despliegue y Flujo CI/CD - TEMPLATE

Este documento detalla cómo funciona el ciclo de vida de la aplicación, desde la ejecución local en la computadora del desarrollador hasta su publicación automatizada en los diferentes entornos de Azure (Desarrollo, Pre-producción y Producción).

---

## 1. Local vs. Nube: Conceptos Base

El proyecto tiene dos formas principales de ejecutarse:

### Entorno Local (`docker-compose.dev.yml`) y la magia del archivo `.env`
- **Propósito:** Desarrollo rápido e iteración ("Hot Reload") sin comprometer secretos.
- **Flujo:** Utiliza Docker para montar volúmenes locales. Ejecuta el comando `dotnet watch run`, que detecta cada vez que guardas un archivo de código y reinicia la aplicación de forma automática sin reconstruir toda la imagen.
- **Configuración y Jerarquía de Archivos:**
  Cuando levantas el proyecto localmente mediante Docker Compose, la configuración del Backend (.NET) se construye como un "pastel de varias capas" en este orden:
  1. **`appsettings.json`**: Se carga primero, tiene las configuraciones globales o base.
  2. **`appsettings.Development.json`**: Se sobrepone al anterior. Docker lo activa e inyecta porque dentro de tu archivo `.env` tienes declarada la clave `ASPNETCORE_ENVIRONMENT=Development`. Es el lugar perfecto para escribir cosas no sensibles pero útiles de local (por ejemplo, cambiar la cadena de conexión a tu Base de Datos local/desarrollo tipo `AzureSql` sin afectar el JSON principal).
  3. **Variables de Entorno (Archivo `.env`)**: Se cargan al final y **tienen el poder absoluto, sobrescribiendo los archivos JSON anteriores**. 
     - Este archivo nunca se sube a GitHub porque contiene las cosas realmente sensibles, como certificados encriptados SAML2 (`Saml2__SigningCertificatePassword`), contraseñas o el Client Secret de PowerBI (`ConnectionPowerBi__ClientSecret`).
     - **Tip técnico:** Para reemplazar un valor de JSON anidado, .NET utiliza doble guion bajo `__`. Es decir, definir `Saml2__SigningCertificate` en el `.env` es el equivalente directo de ir al archivo `appsettings.json` e inyectarlo dentro del bloque de configuración `{ "Saml2" : { "SigningCertificate" : "..." } }`.

### Entornos de Nube (Azure Web Apps via GitHub Actions)
- **Propósito:** Alojar la aplicación para usuarios (testers, clientes, negocio) con alta seguridad y empaquetado optimizado (`Release`).
- **Flujo:** Nadie publica manualmente desde su computadora. En su lugar, cuando se hace un *push* a ramas específicas, **GitHub Actions** descarga el código, inyecta las credenciales/servidores correctos de forma dinámica, compila ambos proyectos (Angular y .NET) y los envía a Azure.

---

## 2. Los tres entornos (DEVL, PPRD, PROD)

El ciclo de integración y despliegue continuo (CI/CD) está dividido en tres ramas de código principales y tres web apps en Azure separadas:

| Ramas Git | Ambiente | Web App objetivo en Azure | Workflow de GitHub |
| :--- | :--- | :--- | :--- |
| `develop` | **DEVL** (Desarrollo) | `secihti7dev` | `fixci-cd_secihti7dev.yml` |
| `release` | **PPRD** (Pre-Producción) | `WA-PPRD-TEMPLATE` | `fixci-cd_wa-pprd-secihti7d.yml` |
| `main` | **PROD** (Producción) | `WA-PROD-TEMPLATE` | `ci-cd-main_wa-prod-secihti7d.yml` |

> [!NOTE]
> A medida que la aplicación avanza hacia PROD, los flujos de GitHub se vuelven más estrictos. Por ejemplo, en PPRD y PROD, el pipeline se encarga de detener la aplicación de Azure (`type: 'stop'`), limpiar los archivos de destino (`clean: true`), publicar, y finalmente realizar un test (*curl*) levantando el servidor. Esto evita que los archivos queden bloqueados mientras un usuario los visita.

---

## 3. Configuración Dinámica del Backend (.NET)

Para garantizar la seguridad y el aislamiento entre ambientes, el código fuente oficial del repositorio **NO contiene las conexiones, las URL exactas ni las contraseñas** reales para la nube.

Instead, GitHub Actions tiene Variables de Entorno (`vars.DEVL_JSON`, `vars.PPRD_JSON`, `vars.PROD_JSON`) configuradas dentro del portal de GitHub.

**Paso clave en el workflow:**
```bash
echo '${{vars.PROD_JSON}}' > appsettings.json
```

**¿Qué efecto tiene esto?**
Antes de hacer la compilación final (`dotnet publish`), GitHub borra todo lo que trajiste en el repositorio para `appsettings.json` y lo reemplaza con un JSON perfecto de esa variable. Esto cambia dinámicamente los siguientes accesos:
1. **AllowedOrigins (CORS):** Define si acepta tráfico de `https://secihti7dev.azurewebsites.net` o el dominio oficial `https://secihti7d.tec.mx`.
2. **Key Vault:** La bóveda de secretos cambia. Dev no puede leer los secretos de Prod.
3. **Autenticación (SAML2):** Reemplazan las URLs de Single Sign On, cambiando de dominios de prueba (`amfsdevl.tec.mx`) a los de producción (`amfs.tec.mx`), así como las redirecciones seguras permitidas (*AssertionConsumerService*).

### 3.1. El Rol y Flujo del Azure Key Vault
El archivo `.env` o el `appsettings.json` te dan la URL del servidor seguro (`KeyVaultUri`), pero los secretos reales (contraseñas de la base de datos, Client Secrets, certificados) viven exclusivamente en la bóveda de Azure. 

De acuerdo a cómo está construido tu archivo `Program.cs`, **el ciclo de los secretos de Key Vault es el siguiente:**

1. **GitHub Actions no lee secretos:** Durante el despliegue automático, la nube solo cambia la URL que apunta a la bóveda, pero jamás extrae contraseñas. El código se empaca limpio y sin secretos.
2. **Arranque en Azure Server (Runtime):** Cuando la Web App de Azure prende el servidor, .NET ejecuta `Program.cs`. En ese instante, la aplicación usa una identidad administrada (`DefaultAzureCredential`) para "tocarle la puerta" al Key Vault asociado a su ambiente.
3. **Inyección en Memoria:** Descarga los secretos y los mezcla directamente en la memoria. Por ejemplo, en Azure Key Vault puedes tener un secreto llamado `ConnectionPowerBi--ClientSecret`, y .NET lo asimilará instantáneamente como si estuviera en el `appsettings.json`.
4. **¿Por qué falla si no tengo el `.env` cuando programo local?:** Revisando tu código en `Program.cs`, existe esta validación: `if (!env.IsDevelopment())`. Esto significa que **cuando levantas el Docker**, el sistema salta la parte de conectarse a Azure Key Vault. Ya que localmente estás desconectado de esa bóveda de la nube, ¡te conviertes en tu propio Key Vault! Esa es la principal razón por la que siempre debes suministrar las llaves secretas o la cadena real a mano dentro del bloque de tu `.env` o tu `appsettings.Development.json`.

---

## 4. Configuración Dinámica del Frontend (Angular)

Así como el Backend cambia su configuración mediante el `appsettings.json`, el **Frontend (ClientApp)** necesita compilarse de diferente manera dependiendo del entorno (para usar las variables de entorno de Angular desde su carpeta `environments/`).

Para lograr esto, las Actions combinan esfuerzos con el archivo del proyecto `TEMPLATE.csproj`.

**En el flujo de trabajo (.yml):**
Se define qué definición usar, por ejemplo:
```yaml
env:
  Build_DefinitionName: 'BackOfficePROD'
```

**En el archivo TEMPLATE.csproj:**
El archivo del proyecto detecta esta variable y ejecuta automáticamente el script de `npm` que le corresponde:
```xml
<Exec WorkingDirectory="$(SpaRoot)" Command="npm run build:PROD" Condition=" '$(Build_DefinitionName)' == 'BackOfficePROD'"/>   
<Exec WorkingDirectory="$(SpaRoot)" Command="npm run build:PPRD" Condition="'$(Build_DefinitionName)' == 'BackOfficePPRD'"/>
<Exec WorkingDirectory="$(SpaRoot)" Command="npm run build:DEVL" Condition="'$(Build_DefinitionName)' == 'BackOfficeDEVL'"/>
```

**¿Qué efecto tiene esto?**
El comando `npm run build:XXX` tomará toda la aplicación de Angular, reemplazará el `environment.ts` base con el de PPRD/PROD/DEVL, construirá los binarios optimizados (JavaScript estático dentro de `/dist`), y .NET recogerá esa carpeta y la empaquetará junto a la DLL de backend.

---

## 5. Resumen del Flujo Completo paso a paso.

Cada vez que se hace un *Push* en las ramas principales, este es el ciclo de vida en los "Runners" de GitHub de principio a fin:

1. **Checkout**: GitHub descarga una copia limpia de la respectiva rama.
2. **Update Settings**: Se inyecta la variable JSON del ambiente correspondiente en el archivo `appsettings.json` del código fuente. (Backend Configurado ✅).
3. **Setup .NET**: Instala la versión de .NET 8 necesaria. En PPRD y PROD, aplica borrado de caches y recupero de paquetes limpio (`dotnet clean` y `dotnet restore`).
4. **Publish**: Inicia la compilación del código .NET mediante `dotnet publish -c Release --no-restore --no-build` (en PROD/PPRD aseguran no volver a realizar el build/restore que ya se hizo, ahorrando tiempo).
5. **Interceptación del CSPROJ**: Cuando la herramienta de Microsoft detecta que debe hacer el publish, llama internamente a instalar los paquetes (`npm install`) y a construir el frontend (`npm run build:xxx` dependiendo del entorno configurado). (Frontend Configurado ✅).
6. **Empaquetado final**: .NET incluye los archivos finales compilados de Angular dentro de la salida nativa (`/myapp`).
7. **Detención**: *(Solo PPRD y PROD)* Se envía un comando a Azure ordenando la detención preventiva del Azure Web App para soltar los bloqueos de lectura de archivos.
8. **Despliegue a Azure**: El artefacto final comprimido se envía al App Service usando el perfil de publicación seguro (`publish-profile`). Activando la opción `clean: true`, Azure borra los archivos viejos y coloca solo los nuevos.
9. **Reanudación y Smoke Test**: *(Solo PPRD y PROD)* Arranca la aplicación nuevamente de forma forzada (`restart: true`) en Azure y el workflow realiza peticiones y pausas de 30 segundos con un `curl` (petición web) para encender la aplicación y validar que todo esté operando correctamente.

> [!WARNING]
> Dado que este flujo de construcción está fuertemente acoplado, si tienes un error local en tu código de TypeScript que impide compilar Angular o un error de sintaxis en los JSON almacenados en GitHub Actions... **fallará todo el despliegue**. Asegúrate de validar localmente los builds antes de hacer push en ramas clave.
