prefix              = "lab8"
location            = "eastus"
vm_count            = 2
admin_username      = "student"
ssh_public_key      = "~/.ssh/id_ed25519.pub"
allow_ssh_from_cidr = "190.158.204.58/32" # Reemplaza por tu IP publica actual/32
tags                = { owner = "santiago", course = "ARSW/BluePrints", env = "dev", expires = "2026-12-31" }
