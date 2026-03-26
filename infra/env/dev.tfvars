prefix   = "lab8"
location = "eastus2"
vm_count = 2
admin_username = "student"
ssh_public_key = "~/.ssh/id_ed25519.pub"
allow_ssh_from_cidr = "186.84.20.2/32" # Cambia a tu IP/32
tags = { owner = "alias", course = "ARSW", env = "dev", expires = "2025-12-31" }
