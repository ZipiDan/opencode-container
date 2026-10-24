// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

//! Información del SO: parseo de /etc/os-share compartido por el fallback bwrap
//! (hints de instalación) y la auditoría (validación de distro soportada).

/// Lee un campo de /etc/os-release sin comillas (None si no existe el archivo/campo).
pub fn field(key: &str) -> Option<String> {
    let content = std::fs::read_to_string("/etc/os-release").ok()?;
    content
        .lines()
        .find(|l| l.starts_with(&format!("{key}=")))
        .map(|l| {
            l.split_once('=')
                .map(|x| x.1)
                .unwrap_or("")
                .trim_matches('"')
                .to_string()
        })
}

/// Devuelve (ID, ID_LIKE) del sistema (vacíos si no se puede leer).
pub fn id_and_like() -> (String, String) {
    (
        field("ID").unwrap_or_default(),
        field("ID_LIKE").unwrap_or_default(),
    )
}

/// ¿Distro soportada por landlock_rosh? Familias: debian/rhel/fedora/suse/arch/alpine/gentoo.
/// En Err devuelve una descripción lista para mostrar al usuario.
pub fn distro_supported() -> Result<(), String> {
    let (id, like) = id_and_like();
    const IDS: &[&str] = &[
        "debian",
        "ubuntu",
        "linuxmint",
        "lmde",
        "raspbian",
        "proxmox",
        "fedora",
        "rhel",
        "centos",
        "rocky",
        "almalinux",
        "ol",
        "opensuse",
        "opensuse-leap",
        "opensuse-tumbleweed",
        "sles",
        "arch",
        "manjaro",
        "endeavouros",
        "alpine",
        "gentoo",
    ];
    const LIKES: &[&str] = &["debian", "rhel", "fedora", "suse", "arch"];
    if IDS.contains(&id.as_str()) || LIKES.iter().any(|f| like.contains(f)) {
        Ok(())
    } else {
        Err(format!(
            "distro no soportada (ID={id}, ID_LIKE={like}); no se realizó ningún cambio"
        ))
    }
}

/// Comando de instalación de un paquete según la distro detectada.
/// None si la distro no se reconoce (misma tabla que usa el fallback bwrap).
pub fn pkg_install_hint(pkg: &str) -> Option<String> {
    let (id, like) = id_and_like();
    match id.as_str() {
        "debian" | "ubuntu" | "linuxmint" | "lmde" | "raspbian" => {
            Some(format!("apt-get install -y {pkg}"))
        }
        "fedora" => Some(format!("dnf install -y {pkg}")),
        "rhel" | "centos" | "rocky" | "almalinux" | "ol" => Some(format!(
            "dnf install -y epel-release && dnf install -y {pkg}"
        )),
        "opensuse" | "opensuse-leap" | "opensuse-tumbleweed" | "sles" => {
            Some(format!("zypper install -y {pkg}"))
        }
        "arch" | "manjaro" | "endeavouros" => Some(format!("pacman -S --noconfirm {pkg}")),
        "alpine" => Some(format!("apk add --no-cache {pkg}")),
        "gentoo" => Some(format!("emerge --ask=n {pkg}")),
        _ => {
            if like.contains("debian") {
                Some(format!("apt-get install -y {pkg}"))
            } else if like.contains("rhel") || like.contains("fedora") {
                Some(format!("dnf install -y {pkg}"))
            } else if like.contains("suse") {
                Some(format!("zypper install -y {pkg}"))
            } else if like.contains("arch") {
                Some(format!("pacman -S --noconfirm {pkg}"))
            } else {
                None
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debian_container_es_soportado() {
        assert!(distro_supported().is_ok());
    }

    #[test]
    fn campo_inexistente_da_none() {
        assert!(field("NO_EXISTE_XYZ").is_none());
    }

    #[test]
    fn hint_para_debian_usa_apt() {
        let hint = pkg_install_hint("bubblewrap").unwrap_or_default();
        assert!(hint.contains("apt-get"), "hint: {hint}");
    }
}
