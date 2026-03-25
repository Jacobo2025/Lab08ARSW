# Lab #8 — Infraestructura como Código con Terraform (Azure)
**Curso:** BluePrints / ARSW  
**Duración estimada:** 2–3 horas (base) + 1–2 horas (retos)  
**Última actualización:** 2025-11-09

## Propósito
Modernizar el laboratorio de balanceo de carga en Azure usando **Terraform** para definir, aprovisionar y versionar la infraestructura. El objetivo es que los estudiantes diseñen y desplieguen una arquitectura reproducible, segura y con buenas prácticas de _IaC_.

## Objetivos de aprendizaje
1. Modelar infraestructura de Azure con Terraform (providers, state, módulos y variables).
2. Desplegar una arquitectura de **alta disponibilidad** con **Load Balancer** (L4) y 2+ VMs Linux.
3. Endurecer mínimamente la seguridad: **NSG**, **SSH por clave**, **tags**, _naming conventions_.
4. Integrar **backend remoto** para el _state_ en Azure Storage con _state locking_.
5. Automatizar _plan_/**apply** desde **GitHub Actions** con autenticación OIDC (sin secretos largos).
6. Validar operación (health probe, página de prueba), observar costos y destruir con seguridad.

> **Nota:** Este lab reemplaza la versión clásica basada en acciones manuales. Enfócate en _IaC_ y _pipelines_.

---

## Arquitectura objetivo
- **Resource Group** (p. ej. `rg-lab8-<alias>`)
- **Virtual Network** con 2 subredes:
  - `subnet-web`: VMs detrás de **Azure Load Balancer (público)**
  - `subnet-mgmt`: Bastion o salto (opcional)
- **Network Security Group**: solo permite **80/TCP** (HTTP) desde Internet al LB y **22/TCP** (SSH) solo desde tu IP pública.
- **Load Balancer** público:
  - Frontend IP pública
  - Backend pool con 2+ VMs
  - **Health probe** (TCP/80 o HTTP)
  - **Load balancing rule** (80 → 80)
- **2+ VMs Linux** (Ubuntu LTS) con cloud-init/Custom Script Extension para instalar **nginx** y servir una página con el **hostname**.
- **Azure Storage Account + Container** para Terraform **remote state** (con bloqueo).
- **Etiquetas (tags)**: `owner`, `course`, `env`, `expires`.

> **Opcional** (retos): usar **VM Scale Set**, o reemplazar LB por **Application Gateway** (L7).

---

## Requisitos previos
- Cuenta/Subscription en Azure (Azure for Students o equivalente).
- **Azure CLI** (`az`) y **Terraform >= 1.6** instalados en tu equipo.
- **SSH key** generada (ej. `ssh-keygen -t ed25519`).
- Cuenta en **GitHub** para ejecutar el pipeline de Actions.

---

## Estructura del repositorio (sugerida)
```
.
├─ infra/
│  ├─ main.tf
│  ├─ providers.tf
│  ├─ variables.tf
│  ├─ outputs.tf
│  ├─ backend.hcl.example
│  ├─ cloud-init.yaml
│  └─ env/
│     ├─ dev.tfvars
│     └─ prod.tfvars (opcional)
├─ modules/
│  ├─ vnet/
│  │  ├─ main.tf
│  │  ├─ variables.tf
│  │  └─ outputs.tf
│  ├─ compute/
│  │  ├─ main.tf
│  │  ├─ variables.tf
│  │  └─ outputs.tf
│  └─ lb/
│     ├─ main.tf
│     ├─ variables.tf
│     └─ outputs.tf
└─ .github/workflows/terraform.yml
```

---

## Bootstrap del backend remoto
Primero crea el **Resource Group**, **Storage Account** y **Container** para el _state_:

```bash
# Nombres únicos
SUFFIX=$RANDOM
LOCATION=eastus
RG=rg-tfstate-lab8
STO=sttfstate${SUFFIX}
CONTAINER=tfstate

az group create -n $RG -l $LOCATION
az storage account create -g $RG -n $STO -l $LOCATION --sku Standard_LRS --encryption-services blob
az storage container create --name $CONTAINER --account-name $STO
```

Completa `infra/backend.hcl.example` con los valores creados y renómbralo a `backend.hcl`.

---

## Variables principales (ejemplo)
En `infra/variables.tf` define:
- `prefix`, `location`, `vm_count`, `admin_username`, `ssh_public_key`
- `allow_ssh_from_cidr` (tu IPv4 en /32)
- `tags` (map)

En `infra/env/dev.tfvars`:
```hcl
prefix        = "lab8"
location      = "eastus"
vm_count      = 2
admin_username= "student"
ssh_public_key= "~/.ssh/id_ed25519.pub"
allow_ssh_from_cidr = "X.X.X.X/32" # TU IP
tags = { owner = "tu-alias", course = "ARSW/BluePrints", env = "dev", expires = "2025-12-31" }
```

---

## cloud-init de las VMs
Archivo `infra/cloud-init.yaml` (instala nginx y muestra el hostname):
```yaml
#cloud-config
package_update: true
packages:
  - nginx
runcmd:
  - echo "Hola desde $(hostname)" > /var/www/html/index.nginx-debian.html
  - systemctl enable nginx
  - systemctl restart nginx
```

---

## Flujo de trabajo local
```bash
cd infra

# Autenticación en Azure
az login
az account show # verifica la suscripción activa

# Inicializa Terraform con backend remoto
terraform init -backend-config=backend.hcl

# Revisión rápida
terraform fmt -recursive
terraform validate

# Plan con variables de dev
terraform plan -var-file=env/dev.tfvars -out plan.tfplan

# Apply
terraform apply "plan.tfplan"

# Verifica el LB público (cambia por tu IP)
curl http://$(terraform output -raw lb_public_ip)
```

**Outputs esperados** (ejemplo):
- `lb_public_ip`
- `resource_group_name`
- `vm_names`

---

## GitHub Actions (CI/CD con OIDC)
El _workflow_ `.github/workflows/terraform.yml`:
- Ejecuta `fmt`, `validate` y `plan` en cada PR.
- Publica el plan como artefacto/comentario.
- Job manual `apply` con _workflow_dispatch_ y aprobación.

**Configura OIDC** en Azure (federación con tu repositorio) y asigna el rol **Contributor** al _principal_ del _workflow_ sobre el RG del lab.

---

## Entregables en TEAMS
1. **Repositorio GitHub** del equipo con:
   - Código Terraform (módulos) y `cloud-init.yaml`.
   - `backend.hcl` **(sin secretos)** y `env/dev.tfvars` (sin llaves privadas).
   - Workflow de GitHub Actions y evidencias del `plan`.
2. **Diagrama** (componente y secuencia) del caso de estudio propuesto.
3. **URL/IP pública** del Load Balancer + **captura** mostrando respuesta de **2 VMs** (p. ej. refrescar y ver hostnames cambiar).
4. **Reflexión técnica** (1 página máx.): decisiones, trade‑offs, costos aproximados y cómo destruir seguro.
5. **Limpieza**: confirmar `terraform destroy` al finalizar.

---

## Rúbrica (100 pts)
- **Infra desplegada y funcional (40 pts):** LB, 2+ VMs, health probe, NSG correcto.
- **Buenas prácticas Terraform (20 pts):** módulos, variables, `fmt/validate`, _remote state_.
- **Seguridad y costos (15 pts):** SSH por clave, NSG mínimo, tags y _naming_; estimación de costos.
- **CI/CD (15 pts):** pipeline con `plan` automático y `apply` manual (OIDC).
- **Documentación y diagramas (10 pts):** README del equipo, diagramas claros y reflexión.

---

## Retos (elige 2+)
- Migrar a **VM Scale Set** con _Custom Script Extension_ o **cloud-init**.
- Reemplazar LB por **Application Gateway** con _probe_ HTTP y _path-based routing_ (si exponen múltiples apps).
- **Azure Bastion** para acceso SSH sin IP pública en VMs.
- **Alertas** de Azure Monitor (p. ej. estado del probe) y **Budget alert**.
- **Módulos privados** versionados con _semantic versioning_.

---

## Limpieza
```bash
terraform destroy -var-file=env/dev.tfvars
```

> **Tip:** Mantén los recursos etiquetados con `expires` y **elimina** todo al terminar.

---

## Preguntas de reflexión
- ¿Por qué L4 LB vs Application Gateway (L7) en tu caso? ¿Qué cambiaría?
- ¿Qué implicaciones de seguridad tiene exponer 22/TCP? ¿Cómo mitigarlas?
- ¿Qué mejoras harías si esto fuera **producción**? (resiliencia, autoscaling, observabilidad).

---

## Créditos y material de referencia
- Azure, Terraform, IaC, LB y VMSS (docs oficiales) — revisa enlaces en clase.

----
# INFORME DE LABORATORIO

**Autores**:
- *Jacobo Diaz Alvarado*
- *Santiago Carmona Pineda*
---
## PARTE I
**Entendiendo la estructura**:

`/infra`: 

- `/env`: tiene un archivo llamado `dev.tfvars` que contiene el formulario de configuración de la infraestructura. Cada línea le dice a *Terraform* cómo se quiere crear la infraestructura.



  - prefix -> Nombre de todos los recursos.
  - location -> En qué datacenter de Azure se van a crear los recursos.
  - vm_count -> Cuantas máquinas virtuales se quieren.
  - admin_username -> El nombre del usuario con el que se conectará por SSH a las VMs.
  - ssh_public_key -> Llave pública SSH que se instalará en las VMs
  - allow_ssh_from_cidr -> Desde que *ip* se quiere hacer *SSH*
  - tags -> etiquetas para organizar e identificar los recursos en Azure.

- `backend.hcl.example`: Este archivo le dice a Terraform dónde guardar el estado remoto en Azure. 
  - resource_group_name -> El Resource Group de Azure donde vivirá el Storage Account. 
  - storage_account_name -> Disco duro en la nube.
  - container_name -> Dentro del Storage Account hay "contenedores" .
  - key -> El nombre del archivo dentro del contenedor. 


  > Azure → Resource Group → Storage Account → Contenedor → Archivo

- `cloud-init.yaml`: Este archivo es un script de arranque
  - **#cloud-config**: Le dice al sistema que este archivo es un script de cloud-init. 
  - **package_update**: Antes de instalar cualquier cosa, actualiza la lista de paquetes disponibles. 
  - **packages: - nginx**: Instala nginx, que es el servidor web que responde cuando Load Balancer mande tráfico a la VM.
  - **runcmd**: Todo lo que está debajo se ejecuta como comandos en la terminal
- `main.tf`: Su trabajo es crear el Resource Group y luego llamar a los módulos pasándoles la información que necesitan.

- `outputs.tf`: Son los valores que Terraform imprime cuando termina el apply.
  - **lb_public_ip**: la IP pública del Load Balancer. 
  - **resource_group_name**:  el nombre del Resource Group creado. 
  - **vm_names**: los nombres de las VMs
- `providers.tf`: Le dice a Terraform con qué herramientas trabajar y dónde guardar el estado.
  - **required_version**: El Terraform instalado debe ser 1.6 o mayor.
  - **required_providers**: Descarga el plugin de Azure (azurerm) versión 4.x. 

  - **backend "azurerm" {}**: Significa que la configuración del backend vendrá desde afuera, del archivo backend.hcl que pasarás con -backend-config=backend.hcl.
  - **provider "azurerm" { features {} }**: Inicializa el proveedor de Azure

- `variables.tf`: Este archivo declara qué variables existen pero sin valores. 

`/modules`:

- `/compute`:
  - `main.tf`: Crea las NICs y las VMs en Azure usando count para 
    generar N copias. Instala nginx via cloud-init al arrancar.
  - `outputs.tf`: Expone vm_names y nic_ids para que el módulo lb 
    pueda asociar las NICs al backend pool.
  - `variables.tf`: Recibe todo lo necesario para crear las VMs:
    credenciales, subnet, cloud-init, cantidad de VMs y tags.

- `/lb`:
  - `main.tf`: Crea la IP pública, el Load Balancer, el backend pool, 
    el health probe, la regla de balanceo y el NSG con sus reglas.
  - `outputs.tf`: Expone public_ip para que infra/outputs.tf pueda 
    mostrártela al final del apply.
  - `variables.tf`: Recibe las NICs de las VMs, tu IP para SSH y 
    los datos básicos del Resource Group.

- `/vnet`:
  - `main.tf`: Crea la Virtual Network (el edificio) y dos subnets 
    dentro de ella: subnet-web para las VMs y subnet-mgmt para 
    administración.
  - `outputs.tf`: Expone subnet_web_id para que el módulo compute 
    sepa en qué subred colocar las VMs.
  - `variables.tf`: Recibe los datos básicos: resource group, 
    location, prefix y tags.
 


