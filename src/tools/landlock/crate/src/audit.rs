// SPDX-FileCopyrightText: 2026 Daniel Zipitría (Calisto)
// SPDX-License-Identifier: MPL-2.0

//! Auditoría de comandos ejecutados bajo landlock_rosh (v1.6).
//!
//! Backends autodetectados por artefactos reales del sistema:
//!   1. journald activo  (/run/systemd/journal/socket) → Backend::Journal
//!   2. backend archivo  (/etc/logrotate.d/landlock_rosh + dir de logs) → Backend::File
//!   3. ninguno                                          → Backend::Disabled
//!
//! Reglas de oro:
//!   - `--no-log` (o env LANDLOCK_NO_LOG=1) fuerza Disabled.
//!   - Un fallo de logging NUNCA bloquea la ejecución del comando (degrada con aviso).
//!   - El fd del recurso se abre ANTES de aplicar el sandbox: Landlock media en open(),
//!     no en write() sobre fds ya abiertos, así no hay que abrir agujeros en la jaula.

use std::io::Write;
use std::os::fd::AsRawFd;
use std::os::unix::net::UnixDatagram;
use std::path::Path;

// --- Paths del sistema ---
const JOURNAL_SOCKET: &str = "/run/systemd/journal/socket";
const LOGROTATE_CONF: &str = "/etc/logrotate.d/landlock_rosh";
const LOG_DIR: &str = "/var/log/landlock_rosh";
const LOG_FILE: &str = "/var/log/landlock_rosh/landlock_rosh.log";
/// Fd fijo que se hereda a bash interactivo para el hook PROMPT_COMMAND.
const ROSH_FD: i32 = 9;
/// Límite por entrada (protege datagramas de journald y líneas gigantes).
const MAX_CMD_LEN: usize = 8192;

pub const LOGROTATE_CONTENT: &str = "\
# Generado por landlock_rosh --install-log. NO editar a mano: se regenera con --install-log.
# Rotación: diaria o al superar 20 MB (lo primero que ocurra). Retención: ~31 rotaciones (~1 mes).
/var/log/landlock_rosh/*.log {
    daily
    maxsize 20M
    rotate 31
    missingok
    notifempty
    compress
    delaycompress
    create 0640 root adm
}
";

/// Recurso de logging ya abierto (pre-sandbox).
pub enum Backend {
    /// Socket datagrama conectado a journald (formato nativo de campos).
    Journal(UnixDatagram),
    /// Logfile abierto en O_APPEND (rotación gestionada por logrotate).
    File(std::fs::File),
    Disabled,
}

/// Metadatos de la sesión, recolectados una sola vez al arrancar.
pub struct SessionMeta {
    pub user: String,
    pub uid: u32,
    pub host: String,
    pub src: String,
    pub mode: String,
}

/// Backend + metadatos, listo para emitir entradas.
pub struct AuditCtx {
    pub backend: Backend,
    pub meta: SessionMeta,
}

impl AuditCtx {
    /// Detecta backend y recolecta metadatos. Nunca falla: si algo no está,
    /// queda Disabled (con aviso a stderr solo si estaba configurado).
    pub fn open(no_log_flag: bool, mode: &str) -> Self {
        let backend = detect_backend(no_log_flag);
        let meta = collect_meta(mode);
        Self { backend, meta }
    }

    pub fn active(&self) -> bool {
        !matches!(self.backend, Backend::Disabled)
    }

    /// Inicio de comando SSH no interactivo.
    pub fn log_cmd_start(&mut self, cmd: &str) {
        self.emit("start", Some(cmd), None);
    }

    /// Fin de comando no interactivo con código de salida.
    pub fn log_cmd_end(&mut self, cmd: &str, code: i32) {
        self.emit("end", Some(cmd), Some(code));
    }

    /// Arranque de shell interactiva (el launcher ve la sesión, no cada tecla).
    pub fn log_session_start(&mut self) {
        self.emit("session-start", None, None);
    }

    /// Evento administrativo (--install-log / --uninstall-log).
    pub fn log_action(&mut self, action: &str) {
        self.emit(action, None, None);
    }

    /// Emite una entrada al backend activo. Best-effort: errores → aviso stderr.
    fn emit(&mut self, event: &str, cmd: Option<&str>, exit: Option<i32>) {
        match &mut self.backend {
            Backend::Journal(sock) => {
                let payload = journal_payload(&self.meta, event, cmd, exit);
                if let Err(e) = sock.send(payload.as_bytes()) {
                    eprintln!("[landlock] aviso auditoría (journal): {e}");
                }
            }
            Backend::File(f) => {
                let line = build_line(&self.meta, event, cmd, exit);
                if let Err(e) = writeln!(f, "{line}") {
                    eprintln!("[landlock] aviso auditoría (archivo): {e}");
                }
            }
            Backend::Disabled => {}
        }
    }

    /// Snippet bash del hook PROMPT_COMMAND para sesiones interactivas.
    /// None si no hay backend activo o el fd heredado no está disponible.
    pub fn rc_hook(&self) -> Option<String> {
        if !self.active() {
            return None;
        }
        let hook = match self.backend {
            // Archivo: línea de texto plano con timestamp local vía date(1).
            Backend::File(_) => {
                r#"
# --- landlock_rosh: auditoria best-effort por comando ---
__rosh_log() {
  local c ts
  c=$(fc -ln -1 2>/dev/null | tr '\t\n' '  ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  c=${c//\\/\\\\}
  c=${c//\"/\\\"}
  [ -z "$c" ] && return 0
  ts=$(date '+%F %T%z')
  printf '%s | %s | %s(%s) | src=%s | mode=%s | inter-cmd | cmd="%s"\n' \
    "$ts" "$HOSTNAME" "${USER:-$(id -un)}" "$(id -u)" "$ROSH_SRC" "$ROSH_MODE" "$c" \
    >&"$ROSH_LOG_FD" 2>/dev/null
}
PROMPT_COMMAND=__rosh_log
"#
            }
            // Journal: datagrama con campos nativos (journald agrega su timestamp).
            Backend::Journal(_) => {
                r#"
# --- landlock_rosh: auditoria best-effort por comando ---
__rosh_log() {
  local c
  c=$(fc -ln -1 2>/dev/null | tr '\t\n' '  ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  c=${c//\\/\\\\}
  c=${c//\"/\\\"}
  [ -z "$c" ] && return 0
  printf 'MESSAGE=%s inter-cmd: %s\nSYSLOG_IDENTIFIER=landlock_rosh\nPRIORITY=6\nLANDLOCK_USER=%s\nLANDLOCK_UID=%s\nLANDLOCK_SRC=%s\nLANDLOCK_MODE=%s\nLANDLOCK_EVENT=inter-cmd\nLANDLOCK_CMD=%s\n' \
    "$ROSH_MODE" "$c" "${USER:-$(id -un)}" "$(id -u)" "$ROSH_SRC" "$ROSH_MODE" "$c" \
    >&"$ROSH_LOG_FD" 2>/dev/null
}
PROMPT_COMMAND=__rosh_log
"#
            }
            Backend::Disabled => return None,
        };
        Some(hook.to_string())
    }

    /// Duplica el fd del backend al fd ROSH_FD (9), limpia CLOEXEC y lo devuelve
    /// para que bash interactivo pueda escribirlo vía $ROSH_LOG_FD.
    pub fn prepare_inherit_fd(&self) -> Option<i32> {
        let raw = match &self.backend {
            Backend::Journal(s) => s.as_raw_fd(),
            Backend::File(f) => f.as_raw_fd(),
            Backend::Disabled => return None,
        };
        unsafe {
            let dup = libc::dup(raw);
            if dup < 0 {
                return None;
            }
            let target = if dup == ROSH_FD {
                dup
            } else {
                if libc::dup2(dup, ROSH_FD) < 0 {
                    libc::close(dup);
                    return None;
                }
                libc::close(dup);
                ROSH_FD
            };
            let flags = libc::fcntl(target, libc::F_GETFD);
            if flags >= 0 {
                libc::fcntl(target, libc::F_SETFD, flags & !libc::FD_CLOEXEC);
            }
            Some(target)
        }
    }
}

/// Detección por artefactos reales (sin marcas en /var/lib):
///   --no-log / env → Disabled; socket journald → Journal; config logrotate+dir → File.
fn detect_backend(no_log_flag: bool) -> Backend {
    if no_log_flag
        || std::env::var("LANDLOCK_NO_LOG")
            .map(|v| v == "1")
            .unwrap_or(false)
    {
        return Backend::Disabled;
    }
    // 1) journald: socket presente → conectar antes de sellar el sandbox.
    if is_socket(JOURNAL_SOCKET) {
        match UnixDatagram::unbound().and_then(|s| s.connect(JOURNAL_SOCKET).map(|_| s)) {
            Ok(s) => return Backend::Journal(s),
            Err(e) => eprintln!("[landlock] aviso auditoría: journal no accesible ({e})"),
        }
    }
    // 2) archivo instalado por --install-log (config + directorio).
    if Path::new(LOGROTATE_CONF).is_file() && Path::new(LOG_DIR).is_dir() {
        match std::fs::OpenOptions::new()
            .append(true)
            .create(true)
            .open(LOG_FILE)
        {
            Ok(f) => return Backend::File(f),
            Err(e) => eprintln!("[landlock] aviso auditoría: {LOG_FILE} no escribible ({e})"),
        }
    }
    Backend::Disabled
}

fn is_socket(path: &str) -> bool {
    use std::os::unix::fs::FileTypeExt;
    std::fs::metadata(path)
        .map(|m| m.file_type().is_socket())
        .unwrap_or(false)
}

/// Recolecta user/uid/host/src una vez por invocación.
fn collect_meta(mode: &str) -> SessionMeta {
    let uid = unsafe { libc::getuid() };
    SessionMeta {
        user: username(uid),
        uid,
        host: hostname(),
        src: ssh_source(),
        mode: mode.to_string(),
    }
}

fn username(uid: u32) -> String {
    unsafe {
        let pw = libc::getpwuid(uid);
        if !pw.is_null() && !(*pw).pw_name.is_null() {
            let name = std::ffi::CStr::from_ptr((*pw).pw_name)
                .to_string_lossy()
                .into_owned();
            if !name.is_empty() {
                return name;
            }
        }
    }
    format!("uid{uid}")
}

fn hostname() -> String {
    let mut buf = [0u8; 256];
    unsafe {
        if libc::gethostname(buf.as_mut_ptr() as *mut libc::c_char, buf.len()) == 0 {
            let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
            let h = String::from_utf8_lossy(&buf[..end]).into_owned();
            if !h.is_empty() {
                return h;
            }
        }
    }
    "desconocido".to_string()
}

/// IP:puerto del cliente SSH (sshd exporta SSH_CONNECTION); "local" en TTY/console.
fn ssh_source() -> String {
    match std::env::var("SSH_CONNECTION") {
        Ok(c) => {
            let parts: Vec<&str> = c.split_whitespace().collect();
            if parts.len() >= 2 {
                format!("{}:{}", parts[0], parts[1])
            } else {
                "local".to_string()
            }
        }
        Err(_) => "local".to_string(),
    }
}

/// Timestamp local TZ del sistema (musl lee /etc/localtime aunque sea estático).
fn now_local() -> String {
    unsafe {
        let t = libc::time(std::ptr::null_mut());
        let mut tm: libc::tm = std::mem::zeroed();
        if libc::localtime_r(&t, &mut tm).is_null() {
            return "ts-error".to_string();
        }
        let off = tm.tm_gmtoff;
        let sign = if off < 0 { '-' } else { '+' };
        let abs = off.unsigned_abs();
        format!(
            "{:04}-{:02}-{:02} {:02}:{:02}:{:02}{}{:02}{:02}",
            tm.tm_year + 1900,
            tm.tm_mon + 1,
            tm.tm_mday,
            tm.tm_hour,
            tm.tm_min,
            tm.tm_sec,
            sign,
            abs / 3600,
            (abs % 3600) / 60
        )
    }
}

/// Sanitiza el comando para logs de una línea (anti-inyección): escapa \n \r " \,
/// reemplaza otros caracteres de control y recorta a MAX_CMD_LEN sin cortar UTF-8.
fn sanitize(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            c if (c as u32) < 0x20 || c as u32 == 0x7f => out.push('?'),
            c => out.push(c),
        }
        if out.len() >= MAX_CMD_LEN {
            break;
        }
    }
    if out.len() > MAX_CMD_LEN {
        // recorte seguro por frontera de char
        let mut cut = MAX_CMD_LEN;
        while !out.is_char_boundary(cut) {
            cut -= 1;
        }
        out.truncate(cut);
    }
    out
}

/// Línea de texto plano para el backend archivo.
fn build_line(meta: &SessionMeta, event: &str, cmd: Option<&str>, exit: Option<i32>) -> String {
    let mut line = format!(
        "{} | {} | {}({}) | src={} | mode={} | {}",
        now_local(),
        meta.host,
        meta.user,
        meta.uid,
        meta.src,
        meta.mode,
        event
    );
    if let Some(c) = cmd {
        line.push_str(&format!(" | cmd=\"{}\"", sanitize(c)));
    }
    if let Some(e) = exit {
        line.push_str(&format!(" | exit={e}"));
    }
    line
}

/// Datagrama con formato nativo de journald (campos separados por \n).
fn journal_payload(
    meta: &SessionMeta,
    event: &str,
    cmd: Option<&str>,
    exit: Option<i32>,
) -> String {
    let mut p = format!(
        "MESSAGE={}\nSYSLOG_IDENTIFIER=landlock_rosh\nPRIORITY=6\nLANDLOCK_HOST={}\nLANDLOCK_USER={}\nLANDLOCK_UID={}\nLANDLOCK_SRC={}\nLANDLOCK_MODE={}\nLANDLOCK_EVENT={}\n",
        build_line(meta, event, cmd, exit),
        meta.host,
        meta.user,
        meta.uid,
        meta.src,
        meta.mode,
        event
    );
    if let Some(c) = cmd {
        p.push_str(&format!("LANDLOCK_CMD={}\n", sanitize(c)));
    }
    if let Some(e) = exit {
        p.push_str(&format!("LANDLOCK_EXIT={e}\n"));
    }
    p
}

/// ¿Hay herramienta de rotación disponible? (binario, cron diario o timer systemd)
fn logrotate_available() -> bool {
    [
        "/usr/sbin/logrotate",
        "/usr/bin/logrotate",
        "/etc/cron.daily/logrotate",
        "/usr/lib/systemd/system/logrotate.timer",
    ]
    .iter()
    .any(|p| Path::new(p).exists())
}

// ---------------------------------------------------------------------------
// Flags administrativas: --install-log / --uninstall-log
// (corren SIN sandbox, exigen root, son idempotentes)
// ---------------------------------------------------------------------------

/// Instala la integración de logging con el SO según lo disponible.
pub fn cli_install() -> ! {
    if unsafe { libc::geteuid() } != 0 {
        fatal("--install-log requiere root (escribe en /etc y /var/log)");
    }
    if let Err(e) = crate::osinfo::distro_supported() {
        fatal(&format!("--install-log: {e}"));
    }

    // --- Backend journal: nada que instalar, validar + evento de prueba ---
    if is_socket(JOURNAL_SOCKET) {
        println!("[landlock] --install-log: journald disponible → logging por systemd journal.");
        let test = "landlock_rosh --install-log: evento de prueba (instalación OK)";
        let payload = format!(
            "MESSAGE={test}\nSYSLOG_IDENTIFIER=landlock_rosh\nPRIORITY=6\nLANDLOCK_EVENT=install-log\n"
        );
        match UnixDatagram::unbound().and_then(|s| s.connect(JOURNAL_SOCKET).map(|_| s))
            .and_then(|s| s.send(payload.as_bytes()))
        {
            Ok(_) => println!("[landlock] evento de prueba enviado. Verifique: journalctl -t landlock_rosh -n 5 --since today"),
            Err(e) => println!("[landlock] aviso: journald no aceptó el datagrama de prueba ({e}); revise 'systemctl status systemd-journald'."),
        }
        println!("[landlock] NOTA: la retención la gestiona journald con su política global (journald.conf no fue modificado).");
        println!("[landlock] Para excluir un usuario/clave del logging use --no-log (ver README).");
        std::process::exit(0);
    }

    // --- Backend archivo: requiere logrotate; sin él, sistema no soportado ---
    if !logrotate_available() {
        let hint = crate::osinfo::pkg_install_hint("logrotate").unwrap_or_else(|| {
            "instale logrotate desde los repositorios de su distribucion".to_string()
        });
        fatal(&format!(
            "--install-log: sin journald ni logrotate → sistema no soportado; no se realizó ningún cambio. Instale logrotate ({hint}) y reintente"
        ));
    }

    // Directorio de logs (0750 root:adm)
    let dir_existed = Path::new(LOG_DIR).exists();
    if let Err(e) = std::fs::create_dir_all(LOG_DIR) {
        fatal(&format!("--install-log: no pude crear {LOG_DIR}: {e}"));
    }
    if !dir_existed {
        set_dir_perms(LOG_DIR, 0o750);
    }

    // Config logrotate (sobrescritura idempotente)
    if let Err(e) = std::fs::write(LOGROTATE_CONF, LOGROTATE_CONTENT) {
        fatal(&format!(
            "--install-log: no pude escribir {LOGROTATE_CONF}: {e}"
        ));
    }

    // Logfile (0640 root:adm si es nuevo; no toca permisos del existente)
    let file_existed = Path::new(LOG_FILE).exists();
    match std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(LOG_FILE)
    {
        Ok(_) => {}
        Err(e) => fatal(&format!("--install-log: no pude crear {LOG_FILE}: {e}")),
    }
    if !file_existed {
        set_file_owner_mode(LOG_FILE, 0o640);
    }

    // Auto-verificación de la config (dry-run de logrotate)
    let check = std::process::Command::new("logrotate")
        .arg("-d")
        .arg(LOGROTATE_CONF)
        .output();
    match check {
        Ok(out) if out.status.success() => {
            println!("[landlock] config logrotate validada (logrotate -d OK).")
        }
        Ok(out) => {
            let err = String::from_utf8_lossy(&out.stderr);
            println!("[landlock] AVISO: 'logrotate -d' reportó problemas:\n{err}")
        }
        Err(e) => println!("[landlock] AVISO: no pude ejecutar 'logrotate -d' ({e})."),
    }

    println!("[landlock] Logging por ARCHIVO instalado:");
    println!("  - Logs:      {LOG_FILE}");
    println!("  - Rotación:  {LOGROTATE_CONF} (daily, maxsize 20M, rotate 31, compress)");
    println!("[landlock] Prueba sugerida: {} ", prueba_hint());
    std::process::exit(0);
}

/// Desinstala la integración (idempotente). Los logs históricos se preservan.
pub fn cli_uninstall() -> ! {
    if unsafe { libc::geteuid() } != 0 {
        fatal("--uninstall-log requiere root (escribe en /etc)");
    }
    let mut cambios = 0;

    // Emitir evento de desinstalación ANTES de quitar los artefactos.
    if Path::new(LOGROTATE_CONF).is_file() || is_socket(JOURNAL_SOCKET) {
        let no_log = false;
        let mut ctx = AuditCtx::open(no_log, "installer");
        ctx.log_action("action=uninstall-log");
    }

    if Path::new(LOGROTATE_CONF).is_file() {
        match std::fs::remove_file(LOGROTATE_CONF) {
            Ok(()) => {
                println!("[landlock] --uninstall-log: quitado {LOGROTATE_CONF}");
                cambios += 1;
            }
            Err(e) => fatal(&format!(
                "--uninstall-log: no pude quitar {LOGROTATE_CONF}: {e}"
            )),
        }
    }
    if Path::new(LOG_DIR).is_dir() {
        println!(
            "[landlock] --uninstall-log: logs históricos conservados en {LOG_DIR} (bórrelos a mano si no los necesita)"
        );
    }
    if cambios == 0 {
        if is_socket(JOURNAL_SOCKET) {
            println!(
                "[landlock] --uninstall-log: no hay artefactos de backend archivo que quitar."
            );
            println!("[landlock] El logging por journal es nativo y no se puede desactivar globalmente sin romper journald;");
            println!("[landlock] para excluir sesiones use --no-log, el wrapper landlock_rosh-nolog o LANDLOCK_NO_LOG=1 (ver README).");
        } else {
            println!(
                "[landlock] --uninstall-log: no había instalación de logging; nada que hacer."
            );
        }
    } else {
        println!("[landlock] Logging por archivo deshabilitado ({cambios} cambio/s).");
    }
    std::process::exit(0);
}

fn prueba_hint() -> String {
    format!(
        "SSH_ORIGINAL_COMMAND='whoami' {} ; cat {LOG_FILE}",
        binario_hint()
    )
}

fn binario_hint() -> String {
    std::env::current_exe()
        .map(|p| p.display().to_string())
        .unwrap_or_else(|_| "./landlock_rosh".to_string())
}

fn set_dir_perms(path: &str, mode: u32) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode));
    let _ = std::process::Command::new("chgrp")
        .args(["-f", "adm", path])
        .output();
}

fn set_file_owner_mode(path: &str, mode: u32) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode));
    let _ = std::process::Command::new("chgrp")
        .args(["-f", "adm", path])
        .output();
}

fn fatal(msg: &str) -> ! {
    eprintln!("[landlock] FATAL: {msg}");
    std::process::exit(1);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sanitiza_newlines_y_comillas() {
        assert_eq!(sanitize("a\nb\"c\\d"), "a\\nb\\\"c\\\\d");
        assert_eq!(sanitize("x\x01y"), "x?y");
    }

    #[test]
    fn linea_de_comando_tiene_campos() {
        let m = SessionMeta {
            user: "adminro".into(),
            uid: 0,
            host: "dell7".into(),
            src: "10.1.0.5:22".into(),
            mode: "landlock-abi6".into(),
        };
        let l = build_line(&m, "end", Some("ls -l"), Some(0));
        assert!(
            l.contains("cmd=\"ls -l\"") && l.contains("exit=0") && l.contains("src=10.1.0.5:22")
        );
    }

    #[test]
    fn payload_journal_tiene_identificador() {
        let m = SessionMeta {
            user: "u".into(),
            uid: 1000,
            host: "h".into(),
            src: "local".into(),
            mode: "bwrap".into(),
        };
        let p = journal_payload(&m, "start", Some("id"), None);
        assert!(p.starts_with("MESSAGE="));
        assert!(p.contains("SYSLOG_IDENTIFIER=landlock_rosh"));
        assert!(p.contains("LANDLOCK_CMD=id"));
    }

    #[test]
    fn detect_sin_artefactos_es_disabled_con_no_log() {
        assert!(matches!(detect_backend(true), Backend::Disabled));
    }
}
