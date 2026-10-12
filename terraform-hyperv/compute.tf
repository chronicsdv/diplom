locals {
  gib          = 1073741824
  cp_names     = [for i in range(var.control_plane_count) : "${var.name_prefix}-cp-${i + 1}"]
  worker_names = [for i in range(var.worker_count) : "${var.name_prefix}-worker-${i + 1}"]
}

# ---------- Control plane ----------
resource "hyperv_vhd" "control_plane" {
  count  = var.control_plane_count
  path   = "${var.disk_path}\\${local.cp_names[count.index]}.vhdx"
  source = var.template_vhd

  lifecycle {
    ignore_changes = [vhd_type]
  }
}

resource "hyperv_machine_instance" "control_plane" {
  count                = var.control_plane_count
  name                 = local.cp_names[count.index]
  path                 = var.vm_path
  generation           = 2
  processor_count      = var.cp_cores
  static_memory        = true
  memory_startup_bytes = var.cp_memory_gb * local.gib
  checkpoint_type      = "Disabled"
  state                = "Running"

  vm_firmware {
    enable_secure_boot = "Off"
    boot_order {
      boot_type           = "HardDiskDrive"
      controller_number   = 0
      controller_location = 0
    }
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = hyperv_vhd.control_plane[count.index].path
  }

  network_adaptors {
    name                = "eth0"
    switch_name         = var.switch_name
    dynamic_mac_address = false
    static_mac_address  = format("00155D0A01%02X", count.index + 1)
  }

  lifecycle {
    ignore_changes = [vm_firmware, vm_processor]
  }
}

# ---------- Workers ----------
resource "hyperv_vhd" "worker" {
  count  = var.worker_count
  path   = "${var.disk_path}\\${local.worker_names[count.index]}.vhdx"
  source = var.template_vhd

  lifecycle {
    ignore_changes = [vhd_type]
  }
}

resource "hyperv_machine_instance" "worker" {
  count                = var.worker_count
  name                 = local.worker_names[count.index]
  path                 = var.vm_path
  generation           = 2
  processor_count      = var.worker_cores
  static_memory        = true
  memory_startup_bytes = var.worker_memory_gb * local.gib
  checkpoint_type      = "Disabled"
  state                = "Running"

  vm_firmware {
    enable_secure_boot = "Off"
    boot_order {
      boot_type           = "HardDiskDrive"
      controller_number   = 0
      controller_location = 0
    }
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = hyperv_vhd.worker[count.index].path
  }

  network_adaptors {
    name                = "eth0"
    switch_name         = var.switch_name
    dynamic_mac_address = false
    static_mac_address  = format("00155D0A02%02X", count.index + 1)
  }

  lifecycle {
    ignore_changes = [vm_firmware, vm_processor]
  }
}
