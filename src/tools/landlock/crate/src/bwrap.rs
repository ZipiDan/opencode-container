// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

//! Fallback para kernels < 5.13 (sin Landlock): bubblewrap con mount namespace read-only.
//!
//! bubblewrap (bwrap) crea un mount namespace donde:
//! - / → read-only (--ro-bind / /)
//! - /dev → tmpfs propio de bwrap (--dev): /dev/null y /dev/zero writable (requisito de
//!   redirección de scripts); /dev/tty solo con TTY real
//! - discos reales → bindeados read-only individualmente (--ro-bind /dev/sdX /dev/sdX):
//!   smartctl/storcli pueden abrirlos en O_RDONLY; el mount RO impide escritura y
//!   creación de nodos
//! - /sys → read-only (necesario para lsblk/smartctl identificar discos)
//! - /proc → procfs
//! - /tmp, /var/tmp → tmpfs writable (requisito)
//!
//! Namespaces: --unshare-user --unshare-ipc (aisla identidad/IPC).
//! NO se unshare: pid (ps aux ve el host), net (gluster necesita red), uts (hostname real
//! para el prompt \h).

use std::process::Command;

/// Devuelve el comando de instalación de bubblewrap según la distro detectada
/// en /etc/os-release (tabla compartida en osinfo). None si no se reconoce.
pub fn install_hint() -> Option<String> {
    crate::osinfo::pkg_install_hint("bubblewrap")
}

/// Construye el comando bwrap para ejecutar el comando dado dentro del sandbox read-only.
/// Nota fds: bwrap moderno NO cierra los fds >2 del proceso interno (verificado
/// empíricamente en bwrap 0.11), así que el fd del log hereda sin flags extra.
/// En bwaps viejos que sí los cierren, el hook interactivo falla en silencio
/// (solo se audita inicio de sesión): degradación aceptable y documentada.
pub fn build_bwrap_cmd(inner: &str) -> Command {
    let mut cmd = Command::new("bwrap");
    // Base: / read-only, /dev propio (null/zero writable), /sys RO, /proc, tmpfs writable.
    cmd.args([
        "--ro-bind",
        "/",
        "/",
        "--dev",
        "/dev",
        "--ro-bind",
        "/sys",
        "/sys",
        "--proc",
        "/proc",
        "--tmpfs",
        "/tmp",
        "--tmpfs",
        "/var/tmp",
        "--unshare-user",
        "--unshare-ipc",
        "--new-session",
        "--die-with-parent",
    ]);
    // Discos reales bindeados read-only (device nodes que existan en el host).
    for d in host_block_devices() {
        cmd.arg("--ro-bind").arg(&d).arg(&d);
    }
    cmd.arg("--").arg("/bin/bash").arg("-c").arg(inner);
    cmd
}

/// Device nodes de bloques/SG del host a exponer read-only para auditoría de discos.
/// En un host real son /dev/sdX, /dev/sgX, /dev/nvmeXnY, /dev/megaraid_sas_ioctl_node.
fn host_block_devices() -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(rd) = std::fs::read_dir("/dev") {
        for e in rd.flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            let is_disk = name.starts_with("sd")
                || name.starts_with("sg")
                || name.starts_with("nvme")
                || name.starts_with("hd")
                || name.starts_with("vd")
                || name.starts_with("xvd")
                || name == "megaraid_sas_ioctl_node";
            if is_disk {
                out.push(format!("/dev/{name}"));
            }
        }
    }
    out
}
