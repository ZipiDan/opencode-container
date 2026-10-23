//! Instalación/desinstalación de landlock_rosh como shell del sistema (v1.7).
//!
//! Flags administrativas (root, SIN sandbox, idempotentes):
//!   --install-shell    → copia el binario a /usr/local/bin/landlock_rosh, crea el
//!                        wrapper sin log (/usr/local/bin/landlock_rosh-nolog) y
//!                        registra AMBAS rutas en /etc/shells.
//!   --uninstall-shell  → operación inversa: quita binario + wrapper y sus entradas
//!                        de /etc/shells. Aborta sin cambios si algún usuario de
//!                        /etc/passwd usa esas shells como login.
//!   --install-ssh      → idem --install-shell + placeholder comentado en
//!                        /root/.ssh/authorized_keys para la clave del agente
//!                        (informe-acceso-landlock-jefe.md §5).
//!   --uninstall-ssh    → quita placeholder comentado + shells (con mismo gate).
//!
//! Adaptación por SO: se valida la distro vía osinfo::distro_supported() antes de
//! tocar nada (mismo criterio que --install-log). Las rutas /usr/local/bin,
//! /etc/shells y el shebang #!/bin/sh son FHS/POSIX comunes a todas las familias
//! soportadas; la variación real es "soportada o no". La arquitectura se detecta
//! con uname(2) solo para el reporte: el binario es estático, si corre ya es
//! compatible por definición.

use std::collections::HashSet;
use std::io;
use std::path::{Path, PathBuf};

// --- Rutas de instalación (FHS, comunes a todas las distros soportadas) ---
const BIN_PATH: &str = "/usr/local/bin/landlock_rosh";
const WRAPPER_PATH: &str = "/usr/local/bin/landlock_rosh-nolog";
const SHELLS_FILE: &str = "/etc/shells";
const DOT_SSH_DIR: &str = "/root/.ssh";
const AUTHORIZED_KEYS: &str = "/root/.ssh/authorized_keys";
/// Opciones sshd comunes a todas las líneas de landlock_rosh.
const SSH_FORCED_OPTS: &str =
    "restrict,no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding";
/// Wrapper sin auditoría (README "Desactivar el log de forma permanente").
/// El "$@" preserva `-c comando` de sshd y el modo login.
const WRAPPER_CONTENT: &str = "#!/bin/sh\nexec /usr/local/bin/landlock_rosh --no-log \"$@\"\n";
const BIN_MODE: u32 = 0o755;

/// Comando forzado según el modo: `ro` (sandbox) o `log` (solo auditoría).
fn forced_command(mode: &str) -> String {
    match mode {
        "log" => format!("{BIN_PATH} --log-only"),
        _ => BIN_PATH.to_string(),
    }
}

/// Línea de authorized_keys que fuerza landlock_rosh para una clave dada.
fn authorized_key_line(mode: &str, pubkey: &str) -> String {
    format!(
        "{SSH_FORCED_OPTS},command=\"{}\" {}",
        forced_command(mode),
        pubkey.trim()
    )
}

/// Placeholder comentado que sugiere el formato al admin.
fn ssh_placeholder() -> String {
    format!(
        "# {}  # descomentar y reemplazar por la clave real del agente",
        authorized_key_line("ro", "ssh-ed25519 AAAA...XXX agente@host")
    )
}

/// Lee la clave pública de un archivo (primera línea no vacía).
fn read_pubkey(path: &str) -> String {
    match std::fs::read_to_string(path) {
        Ok(content) => content
            .lines()
            .map(str::trim)
            .find(|line| !line.is_empty())
            .unwrap_or("")
            .to_string(),
        Err(e) => fatal(&format!("--print-ssh-line: no pude leer {path}: {e}")),
    }
}

/// Imprime la línea de authorized_keys para el modo pedido y sale.
pub fn cli_print_ssh_line(mode: &str, pubkey_path: Option<&str>) -> ! {
    let mode = match mode {
        "ro" | "log" => mode,
        _ => fatal("--print-ssh-line: --mode inválido (usá ro o log)"),
    };
    let pubkey = match pubkey_path {
        Some(path) => read_pubkey(path),
        None => "ssh-ed25519 AAAA...XXX usuario@host".to_string(),
    };
    if pubkey.is_empty() {
        fatal("--print-ssh-line: la clave pública está vacía");
    }
    println!("{}", authorized_key_line(mode, &pubkey));
    std::process::exit(0);
}

// ---------------------------------------------------------------------------
// --install-shell
// ---------------------------------------------------------------------------

/// Lógica común de instalación de shells (binario + wrapper + /etc/shells).
/// Devuelve cantidad de entradas nuevas en /etc/shells. Usada por --install-shell y --install-ssh.
fn instalar_shell_core() -> usize {
    let exe: PathBuf = match std::env::current_exe() {
        Ok(p) => p.canonicalize().unwrap_or(p),
        Err(e) => fatal(&format!(
            "--install-shell: no pude resolver la ruta del binario en ejecución: {e}"
        )),
    };
    instalar_binario(&exe);
    instalar_wrapper();
    registrar_shells(&[BIN_PATH, WRAPPER_PATH])
}

/// Instala binario + wrapper como shells del sistema (idempotente).
pub fn cli_install_shell() -> ! {
    if unsafe { libc::geteuid() } != 0 {
        fatal("--install-shell requiere root (escribe en /usr/local/bin y /etc/shells)");
    }
    if let Err(e) = crate::osinfo::distro_supported() {
        fatal(&format!("--install-shell: {e}"));
    }

    let nuevas = instalar_shell_core();

    // Evento de auditoría best-effort (degrada silencioso si no hay backend).
    auditar_accion("action=install-shell");

    let id = crate::osinfo::field("ID").unwrap_or_else(|| "?".into());
    let like = crate::osinfo::field("ID_LIKE").unwrap_or_else(|| "?".into());
    println!(
        "[landlock] --install-shell: distro {id} (ID_LIKE={like}), arch {} →",
        arch_detectada()
    );
    println!("  - Shell:       {BIN_PATH}");
    println!("  - Wrapper:     {WRAPPER_PATH} (sin auditoría, apto para /etc/passwd)");
    println!("  - {SHELLS_FILE}: {nuevas} entrada/s nueva/s");
    println!("[landlock] Asignar como shell de un usuario:");
    println!("             usermod -s {BIN_PATH} USUARIO   (con auditoría)");
    println!("             usermod -s {WRAPPER_PATH} USUARIO   (sin auditoría)");
    std::process::exit(0);
}

// ---------------------------------------------------------------------------
// --install-ssh / --uninstall-ssh
// ---------------------------------------------------------------------------

/// Instala shells + placeholder comentado en /root/.ssh/authorized_keys (idempotente).
pub fn cli_install_ssh() -> ! {
    if unsafe { libc::geteuid() } != 0 {
        fatal("--install-ssh requiere root (escribe en /usr/local/bin, /etc/shells y /root/.ssh/authorized_keys)");
    }
    if let Err(e) = crate::osinfo::distro_supported() {
        fatal(&format!("--install-ssh: {e}"));
    }

    let nuevas = instalar_shell_core();
    let ssh_res = ensure_ssh_placeholder();

    auditar_accion("action=install-ssh");

    let id = crate::osinfo::field("ID").unwrap_or_else(|| "?".into());
    let like = crate::osinfo::field("ID_LIKE").unwrap_or_else(|| "?".into());
    println!(
        "[landlock] --install-ssh: distro {id} (ID_LIKE={like}), arch {} →",
        arch_detectada()
    );
    println!("  - Shell:       {BIN_PATH}");
    println!("  - Wrapper:     {WRAPPER_PATH} (sin auditoría, apto para /etc/passwd)");
    println!("  - {SHELLS_FILE}: {nuevas} entrada/s nueva/s");
    match ssh_res {
        SshInstallResult::AlreadyActive => {
            println!("  - {AUTHORIZED_KEYS}: ya existe entrada activa con command=\"{BIN_PATH}\" (no se agregó placeholder)");
        }
        SshInstallResult::AlreadyPlaceholder => {
            println!("  - {AUTHORIZED_KEYS}: placeholder ya presente (idempotente)");
        }
        SshInstallResult::Inserted => {
            println!("  - {AUTHORIZED_KEYS}: placeholder comentado agregado");
            println!("[landlock] ACCIÓN REQUERIDA: editar {AUTHORIZED_KEYS}, descomentar la línea y reemplazar AAAA...XXX por la clave real del agente:");
            println!("             {}", ssh_placeholder());
        }
    }
    println!("[landlock] Validar con: sshd -t && cat {AUTHORIZED_KEYS}");
    std::process::exit(0);
}

/// Desinstala placeholder comentado + shells (idempotente, con gate de usuarios).
pub fn cli_uninstall_ssh() -> ! {
    if unsafe { libc::geteuid() } != 0 {
        fatal("--uninstall-ssh requiere root (escribe en /usr/local/bin, /etc/shells y /root/.ssh/authorized_keys)");
    }
    if let Err(e) = crate::osinfo::distro_supported() {
        fatal(&format!("--uninstall-ssh: {e}"));
    }

    // Gate de seguridad: usuarios cuya login shell es alguna de las nuestras.
    let afectados = usuarios_con_shell(&[BIN_PATH, WRAPPER_PATH]);
    if !afectados.is_empty() {
        eprintln!("[landlock] FATAL: --uninstall-ssh abortado: hay usuarios cuya shell de login es landlock_rosh:");
        for u in &afectados {
            eprintln!("  - {u}");
        }
        eprintln!("[landlock] Reasigne su shell primero (ej: chsh -s /bin/bash USUARIO) o elimine las cuentas.");
        eprintln!("[landlock] No se realizó ningún cambio.");
        std::process::exit(1);
    }

    // Auditar ANTES de quitar (si hay algo que quitar).
    let has_ssh_placeholder = Path::new(AUTHORIZED_KEYS).exists()
        && std::fs::read_to_string(AUTHORIZED_KEYS)
            .map(|c| c.lines().any(is_placeholder_line))
            .unwrap_or(false);
    if Path::new(BIN_PATH).exists() || Path::new(WRAPPER_PATH).exists() || has_ssh_placeholder {
        auditar_accion("action=uninstall-ssh");
    }

    let quitados_ssh = remove_ssh_placeholder();
    let mut cambios = 0;
    for (ruta, desc) in [(WRAPPER_PATH, "wrapper"), (BIN_PATH, "binario")] {
        if Path::new(ruta).exists() {
            if let Err(e) = std::fs::remove_file(ruta) {
                fatal(&format!("--uninstall-ssh: no pude quitar {ruta}: {e}"));
            }
            println!("[landlock] --uninstall-ssh: quitado {desc} {ruta}");
            cambios += 1;
        }
    }
    let quitadas_shells = limpiar_shells();

    if quitados_ssh > 0 {
        println!("[landlock] --uninstall-ssh: {quitados_ssh} placeholder(s) comentado(s) quitado(s) de {AUTHORIZED_KEYS}");
        // Verificar si queda entrada activa (no se toca).
        if let Ok(content) = std::fs::read_to_string(AUTHORIZED_KEYS) {
            if content.lines().any(is_active_landlock_line) {
                println!("[landlock] NOTA: queda(n) entrada(s) activa(s) con command=\"{BIN_PATH}\" en {AUTHORIZED_KEYS}; limpie manualmente si ya no se necesita.");
            }
        }
    }

    if cambios == 0 && quitadas_shells == 0 && quitados_ssh == 0 {
        println!("[landlock] --uninstall-ssh: no había instalación de ssh/shells; nada que hacer.");
    } else {
        if quitadas_shells > 0 {
            println!("[landlock] --uninstall-ssh: {quitadas_shells} entrada/s quitada/s de {SHELLS_FILE}");
        }
        if cambios > 0 || quitadas_shells > 0 {
            println!("[landlock] Shells desinstaladas ({cambios} archivo/s).");
        }
    }
    println!(
        "[landlock] NOTA: las entradas activas command=\"{BIN_PATH}\" en {AUTHORIZED_KEYS} NO se tocan automáticamente;"
    );
    println!("[landlock] si instaló una clave real del agente, bórrela a mano cuando corresponda.");
    std::process::exit(0);
}

/// Copia el binario en ejecución al destino final.
/// Caso especial: si ya corre desde el destino solo asegura permisos (evita ETXTBSY).
/// Si otro proceso ejecuta una copia vieja del destino, unlink+copy es seguro:
/// unlink sobre un ejecutable vivo es legal y el proceso conserva su inode.
fn instalar_binario(exe: &Path) {
    let destino = Path::new(BIN_PATH);
    let ya_es_destino = destino.canonicalize().map(|d| d == exe).unwrap_or(false);
    if ya_es_destino {
        asegurar_permisos(BIN_PATH);
        println!("[landlock] binario ya presente en {BIN_PATH} (se ejecuta desde allí; solo perms verificados)");
        return;
    }
    if let Some(padre) = destino.parent() {
        if let Err(e) = std::fs::create_dir_all(padre) {
            fatal(&format!(
                "--install-shell: no pude crear {}: {e}",
                padre.display()
            ));
        }
    }
    let _ = std::fs::remove_file(destino);
    if let Err(e) = std::fs::copy(exe, destino) {
        fatal(&format!(
            "--install-shell: no pude copiar a {BIN_PATH}: {e}"
        ));
    }
    asegurar_permisos(BIN_PATH);
    println!("[landlock] binario copiado a {BIN_PATH}");
}

/// Crea (o reescribe) el wrapper sin log. Siempre se reescribe: corrige drift
/// de ediciones manuales con el mismo criterio idempotente del conf logrotate.
fn instalar_wrapper() {
    if let Err(e) = std::fs::write(WRAPPER_PATH, WRAPPER_CONTENT) {
        fatal(&format!(
            "--install-shell: no pude escribir {WRAPPER_PATH}: {e}"
        ));
    }
    asegurar_permisos(WRAPPER_PATH);
    println!("[landlock] wrapper creado en {WRAPPER_PATH}");
}

/// Registra las rutas en /etc/shells (crea el archivo si falta).
/// Devuelve cuántas entradas eran nuevas (idempotencia real: 0 si ya estaban).
fn registrar_shells(rutas: &[&str]) -> usize {
    let actual = std::fs::read_to_string(SHELLS_FILE).unwrap_or_default();
    let presentes: HashSet<&str> = actual.lines().map(str::trim).collect();
    let nuevas = rutas.iter().filter(|r| !presentes.contains(**r)).count();
    if nuevas > 0 {
        let nuevo = shells_con_entradas(&actual, rutas);
        if let Err(e) = escribir_atomico(SHELLS_FILE, &nuevo) {
            fatal(&format!(
                "--install-shell: no pude actualizar {SHELLS_FILE}: {e}"
            ));
        }
    }
    nuevas
}

// ---------------------------------------------------------------------------
// --uninstall-shell
// ---------------------------------------------------------------------------

/// Desinstala las shells del sistema (idempotente). Preserva logs/usuarios:
/// aborta ANTES de tocar nada si algún usuario depende de estas shells.
pub fn cli_uninstall_shell() -> ! {
    if unsafe { libc::geteuid() } != 0 {
        fatal("--uninstall-shell requiere root (escribe en /usr/local/bin y /etc/shells)");
    }
    if let Err(e) = crate::osinfo::distro_supported() {
        fatal(&format!("--uninstall-shell: {e}"));
    }

    // Gate de seguridad: usuarios cuya login shell es alguna de las nuestras.
    let afectados = usuarios_con_shell(&[BIN_PATH, WRAPPER_PATH]);
    if !afectados.is_empty() {
        eprintln!("[landlock] FATAL: --uninstall-shell abortado: hay usuarios cuya shell de login es landlock_rosh:");
        for u in &afectados {
            eprintln!("  - {u}");
        }
        eprintln!("[landlock] Reasigne su shell primero (ej: chsh -s /bin/bash USUARIO) o elimine las cuentas.");
        eprintln!("[landlock] No se realizó ningún cambio.");
        std::process::exit(1);
    }

    // Evento de auditoría ANTES de quitar artefactos (patrón de --uninstall-log).
    if Path::new(BIN_PATH).exists() || Path::new(WRAPPER_PATH).exists() {
        auditar_accion("action=uninstall-shell");
    }

    // Orden: wrapper primero, binario después (si se corre desde el propio
    // binario instalado, el unlink funciona igual: el proceso vive hasta exit).
    let mut cambios = 0;
    for (ruta, desc) in [(WRAPPER_PATH, "wrapper"), (BIN_PATH, "binario")] {
        if Path::new(ruta).exists() {
            if let Err(e) = std::fs::remove_file(ruta) {
                fatal(&format!("--uninstall-shell: no pude quitar {ruta}: {e}"));
            }
            println!("[landlock] --uninstall-shell: quitado {desc} {ruta}");
            cambios += 1;
        }
    }

    let quitadas_shells = limpiar_shells();

    if cambios == 0 && quitadas_shells == 0 {
        println!("[landlock] --uninstall-shell: no había instalación de shells; nada que hacer.");
    } else {
        if quitadas_shells > 0 {
            println!("[landlock] --uninstall-shell: {quitadas_shells} entrada/s quitada/s de {SHELLS_FILE}");
        }
        println!("[landlock] Shells desinstaladas ({cambios} archivo/s).");
    }
    println!(
        "[landlock] NOTA: los prefijos command=\"{BIN_PATH}\" en authorized_keys quedan huérfanos;"
    );
    println!("[landlock] esas claves NO podrán iniciar sesión hasta limpiarlas (ver README, Escenario 2).");
    std::process::exit(0);
}

/// Filtra las entradas de /etc/shells. Devuelve cuántas quitó (0 si no existe el archivo).
fn limpiar_shells() -> usize {
    let actual = match std::fs::read_to_string(SHELLS_FILE) {
        Ok(s) => s,
        Err(_) => return 0,
    };
    let (nuevo, quitadas) = shells_sin_entradas(&actual, &[BIN_PATH, WRAPPER_PATH]);
    if quitadas > 0 {
        if let Err(e) = escribir_atomico(SHELLS_FILE, &nuevo) {
            fatal(&format!(
                "--uninstall-shell: no pude actualizar {SHELLS_FILE}: {e}"
            ));
        }
    }
    quitadas
}

// ---------------------------------------------------------------------------
// Helpers SSH (/root/.ssh/authorized_keys)
// ---------------------------------------------------------------------------

enum SshInstallResult {
    AlreadyActive,
    AlreadyPlaceholder,
    Inserted,
}

/// ¿La línea contiene el prefijo de landlock_rosh (activa o comentada)?
/// Sin la comilla de cierre: también matchea `--log-only`.
fn contains_landlock_cmd(line: &str) -> bool {
    line.contains(&format!("command=\"{BIN_PATH}"))
}

/// Activa: no comentada y contiene el command.
fn is_active_landlock_line(line: &str) -> bool {
    let t = line.trim_start();
    !t.starts_with('#') && contains_landlock_cmd(line)
}

/// Placeholder: comentada y contiene el command (nuestro template).
fn is_placeholder_line(line: &str) -> bool {
    let t = line.trim_start();
    t.starts_with('#') && contains_landlock_cmd(line)
}

/// Asegura /root/.ssh (0700) y authorized_keys (0600) con placeholder si falta.
/// Idempotente: no duplica si ya hay placeholder o entrada activa.
fn ensure_ssh_placeholder() -> SshInstallResult {
    use std::os::unix::fs::PermissionsExt;

    // Crear /root/.ssh si falta.
    if let Err(e) = std::fs::create_dir_all(DOT_SSH_DIR) {
        fatal(&format!("--install-ssh: no pude crear {DOT_SSH_DIR}: {e}"));
    }
    let _ = std::fs::set_permissions(DOT_SSH_DIR, std::fs::Permissions::from_mode(0o700));

    // Leer contenido existente (o vacío si no existe).
    let actual = std::fs::read_to_string(AUTHORIZED_KEYS).unwrap_or_default();

    // Si ya hay entrada activa, no insertar placeholder (evita duplicar/dar falsa sensación).
    if actual.lines().any(is_active_landlock_line) {
        // Asegurar permisos aunque no se modifique.
        if Path::new(AUTHORIZED_KEYS).exists() {
            let _ =
                std::fs::set_permissions(AUTHORIZED_KEYS, std::fs::Permissions::from_mode(0o600));
        }
        return SshInstallResult::AlreadyActive;
    }
    if actual.lines().any(is_placeholder_line) {
        if Path::new(AUTHORIZED_KEYS).exists() {
            let _ =
                std::fs::set_permissions(AUTHORIZED_KEYS, std::fs::Permissions::from_mode(0o600));
        }
        return SshInstallResult::AlreadyPlaceholder;
    }

    // Insertar placeholder: respetar newline final.
    let mut nuevo = actual;
    if !nuevo.is_empty() && !nuevo.ends_with('\n') {
        nuevo.push('\n');
    }
    nuevo.push_str(&ssh_placeholder());
    nuevo.push('\n');

    // Escritura atómica en el mismo dir (preserva perms 0600).
    let tmp = format!("{AUTHORIZED_KEYS}.rosh-tmp.{}", std::process::id());
    if let Err(e) = std::fs::write(&tmp, &nuevo) {
        fatal(&format!("--install-ssh: no pude escribir placeholder: {e}"));
    }
    let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600));
    if let Err(e) = std::fs::rename(&tmp, AUTHORIZED_KEYS) {
        let _ = std::fs::remove_file(&tmp);
        fatal(&format!(
            "--install-ssh: no pude actualizar {AUTHORIZED_KEYS}: {e}"
        ));
    }
    // Asegurar perms dir también tras rename.
    let _ = std::fs::set_permissions(DOT_SSH_DIR, std::fs::Permissions::from_mode(0o700));
    SshInstallResult::Inserted
}

/// Quita solo placeholders comentados (preserva entradas activas reales).
/// Devuelve cantidad quitada.
fn remove_ssh_placeholder() -> usize {
    let actual = match std::fs::read_to_string(AUTHORIZED_KEYS) {
        Ok(s) => s,
        Err(_) => return 0,
    };
    let mut quedan: Vec<&str> = Vec::new();
    let mut quitados = 0;
    for linea in actual.lines() {
        if is_placeholder_line(linea) {
            quitados += 1;
        } else {
            quedan.push(linea);
        }
    }
    if quitados > 0 {
        let mut nuevo = quedan.join("\n");
        if !nuevo.is_empty() {
            nuevo.push('\n');
        }
        // Si queda vacío, truncamos archivo (preservar perms). Alternativa: quitar duplicado.
        let tmp = format!("{AUTHORIZED_KEYS}.rosh-tmp.{}", std::process::id());
        if let Err(e) = std::fs::write(&tmp, &nuevo) {
            fatal(&format!(
                "--uninstall-ssh: no pude escribir {AUTHORIZED_KEYS}: {e}"
            ));
        }
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(&tmp, std::fs::Permissions::from_mode(0o600));
        if let Err(e) = std::fs::rename(&tmp, AUTHORIZED_KEYS) {
            let _ = std::fs::remove_file(&tmp);
            fatal(&format!(
                "--uninstall-ssh: no pude actualizar {AUTHORIZED_KEYS}: {e}"
            ));
        }
        // Si el archivo quedó vacío, lo dejamos (sshd lo tolera). No borramos el dir.
    }
    quitados
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Usuarios de /etc/passwd cuya shell (campo 7) coincide con alguna ruta dada.
fn usuarios_con_shell(rutas: &[&str]) -> Vec<String> {
    let mut out = Vec::new();
    if let Ok(passwd) = std::fs::read_to_string("/etc/passwd") {
        for linea in passwd.lines() {
            let campos: Vec<&str> = linea.split(':').collect();
            if campos.len() >= 7 && rutas.contains(&campos[6].trim()) {
                out.push(campos[0].to_string());
            }
        }
    }
    out
}

/// Agrega al contenido de /etc/shells las rutas que falten (comparación exacta
/// sobre líneas trimmeadas). Garantiza newline final si agregó entradas.
fn shells_con_entradas(actual: &str, rutas: &[&str]) -> String {
    let presentes: HashSet<&str> = actual.lines().map(str::trim).collect();
    let faltantes: Vec<&str> = rutas
        .iter()
        .copied()
        .filter(|r| !presentes.contains(r))
        .collect();
    if faltantes.is_empty() {
        return actual.to_string();
    }
    let mut out = actual.to_string();
    if !out.is_empty() && !out.ends_with('\n') {
        out.push('\n');
    }
    for f in faltantes {
        out.push_str(f);
        out.push('\n');
    }
    out
}

/// Quita las líneas cuyo contenido (trimmeado) coincida EXACTAMENTE con alguna
/// ruta. Devuelve (contenido_nuevo, cantidad_quitada). Match parcial no cuenta:
/// `/usr/local/bin/landlock_rosh-viejo` sobrevive.
fn shells_sin_entradas(actual: &str, rutas: &[&str]) -> (String, usize) {
    let mut quedan: Vec<&str> = Vec::new();
    let mut quitadas = 0;
    for linea in actual.lines() {
        if rutas.contains(&linea.trim()) {
            quitadas += 1;
        } else {
            quedan.push(linea);
        }
    }
    let mut out = quedan.join("\n");
    if !out.is_empty() {
        out.push('\n');
    }
    (out, quitadas)
}

/// Escritura atómica: temp en el mismo directorio + rename (sin sed/grep externos).
fn escribir_atomico(path: &str, contenido: &str) -> io::Result<()> {
    let tmp = format!("{path}.rosh-tmp.{}", std::process::id());
    std::fs::write(&tmp, contenido)?;
    if let Err(e) = std::fs::rename(&tmp, path) {
        let _ = std::fs::remove_file(&tmp);
        return Err(e);
    }
    Ok(())
}

fn asegurar_permisos(path: &str) {
    use std::os::unix::fs::PermissionsExt;
    if let Err(e) = std::fs::set_permissions(path, std::fs::Permissions::from_mode(BIN_MODE)) {
        fatal(&format!(
            "--install-shell: chmod {:o} {path}: {e}",
            BIN_MODE
        ));
    }
}

/// Arquitectura de máquina (campo machine de uname(2)), para el reporte.
fn arch_detectada() -> String {
    unsafe {
        let mut uts: libc::utsname = std::mem::zeroed();
        if libc::uname(&mut uts) == 0 {
            return std::ffi::CStr::from_ptr(uts.machine.as_ptr())
                .to_string_lossy()
                .into_owned();
        }
    }
    "desconocida".to_string()
}

/// Emite un evento admin al backend activo (patrón de --uninstall-log en audit.rs).
fn auditar_accion(accion: &str) {
    let mut ctx = crate::audit::AuditCtx::open(false, "installer");
    ctx.log_action(accion);
}

fn fatal(msg: &str) -> ! {
    eprintln!("[landlock] FATAL: {msg}");
    std::process::exit(1);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agrega_ambas_si_vacio() {
        let out = shells_con_entradas("", &[BIN_PATH, WRAPPER_PATH]);
        assert_eq!(out, format!("{BIN_PATH}\n{WRAPPER_PATH}\n"));
    }

    #[test]
    fn idempotente_no_duplica() {
        let base = format!("/bin/bash\n{BIN_PATH}\n{WRAPPER_PATH}\n");
        let out = shells_con_entradas(&base, &[BIN_PATH, WRAPPER_PATH]);
        assert_eq!(out, base);
    }

    #[test]
    fn agrega_solo_faltante_con_newline_previo() {
        let out = shells_con_entradas("/bin/bash", &[BIN_PATH]); // sin \n final
        assert_eq!(out, format!("/bin/bash\n{BIN_PATH}\n"));
    }

    #[test]
    fn preserva_otras_lineas_al_quitar() {
        let base = format!("/bin/bash\n{BIN_PATH}\n/usr/bin/zsh\n{WRAPPER_PATH}\n");
        let (out, n) = shells_sin_entradas(&base, &[BIN_PATH, WRAPPER_PATH]);
        assert_eq!(n, 2);
        assert_eq!(out, "/bin/bash\n/usr/bin/zsh\n");
    }

    #[test]
    fn quita_solo_coincidencia_exacta() {
        let base = format!("{BIN_PATH}\n{BIN_PATH}-viejo\n");
        let (out, n) = shells_sin_entradas(&base, &[BIN_PATH]);
        assert_eq!(n, 1);
        assert_eq!(out, format!("{BIN_PATH}-viejo\n"));
    }

    #[test]
    fn quita_en_vacio_da_cero_y_vacio() {
        let (out, n) = shells_sin_entradas("", &[BIN_PATH]);
        assert_eq!(n, 0);
        assert_eq!(out, "");
    }

    #[test]
    fn detecta_usuarios_por_campo_septimo() {
        // simulamos /etc/passwd con tmpfile propio del test (no toca el real)
        let passwd =
            format!("root:x:0:0:root:/root:/bin/bash\npepe:x:1000:1000::/home/pepe:{BIN_PATH}\n");
        let mut afectados = Vec::new();
        for linea in passwd.lines() {
            let campos: Vec<&str> = linea.split(':').collect();
            if campos.len() >= 7 && [BIN_PATH].contains(&campos[6]) {
                afectados.push(campos[0].to_string());
            }
        }
        assert_eq!(afectados, vec!["pepe"]);
    }

    #[test]
    fn ssh_placeholder_es_comentada_con_command() {
        let placeholder = ssh_placeholder();
        assert!(is_placeholder_line(&placeholder));
        assert!(!is_active_landlock_line(&placeholder));
        assert!(contains_landlock_cmd(&placeholder));
    }

    #[test]
    fn linea_ro_fuerza_sandbox() {
        let linea = authorized_key_line("ro", "ssh-ed25519 AAAAB3 agente@host");
        assert!(linea.contains(&format!("command=\"{BIN_PATH}\"")));
        assert!(!linea.contains("--log-only"));
        assert!(is_active_landlock_line(&linea));
    }

    #[test]
    fn linea_log_fuerza_log_only() {
        let linea = authorized_key_line("log", "ssh-ed25519 AAAAB3 agente@host");
        assert!(linea.contains(&format!("command=\"{BIN_PATH} --log-only\"")));
        assert!(is_active_landlock_line(&linea));
    }

    #[test]
    fn ssh_activa_no_es_placeholder() {
        let activa =
            format!("restrict,no-pty,command=\"{BIN_PATH}\" ssh-ed25519 AAAAB3 agente@host");
        assert!(is_active_landlock_line(&activa));
        assert!(!is_placeholder_line(&activa));
    }

    #[test]
    fn ssh_linea_inerte_no_matchea() {
        let otra = "ssh-ed25519 AAAAB3 otra@host";
        assert!(!contains_landlock_cmd(otra));
        assert!(!is_active_landlock_line(otra));
        assert!(!is_placeholder_line(otra));
    }

    #[test]
    fn placeholder_con_espacios_previos_sigue_siendolo() {
        let l = format!("  #  command=\"{BIN_PATH}\" ssh-ed25519 AAA");
        assert!(is_placeholder_line(&l));
    }
}
